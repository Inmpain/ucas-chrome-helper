#!/bin/zsh
# UCAS Chrome 本机识别助手；不读取账号密码，不访问其他域名。
set -euo pipefail
"${UCAS_RUNNER_PYTHON:-/usr/bin/python3}" - <<'PY'
# -*- coding: utf-8 -*-
import json, re, subprocess, time, socket, os
from pathlib import Path

ORIGIN = "https://jwxk.ucas.ac.cn"
# 系统 Vision 在干扰验证码上多次不确定；复用已安装的验证码模型，不新装依赖。
OCR_PYTHON = os.environ.get("UCAS_OCR_PYTHON", str(Path.home()/"UCAS-Desktop/.venv/bin/python"))
OCR_CODE = "import sys,base64,json,ddddocr; m=ddddocr.DdddOcr(show_ad=False); s=m.classification(base64.b64decode(sys.stdin.read().strip())); print(json.dumps({'text':s}))"
def command(args, text=None, timeout=25):
    result = subprocess.run(args, input=text, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:300] or "Command failed")
    return result.stdout.strip()

pid = None
def chrome_pid():
    # 不在开机时启动Chrome；每次查询现有GUI实例，避免重开后继续用旧PID。
    code = """ObjC.import('AppKit');var a=$.NSWorkspace.sharedWorkspace.runningApplications;var found=[];
      for(var i=0;i<a.count;i++){var p=a.objectAtIndex(i);if(ObjC.unwrap(p.bundleIdentifier)==='com.google.Chrome'&&Number(p.activationPolicy)===0)found.push(p.processIdentifier);}
      JSON.stringify(found);"""
    found=json.loads(command(["osascript","-l","JavaScript","-e",code]))
    if not found: return None
    if len(found)!=1: raise RuntimeError("有多个日常Chrome实例，请先保留一个")
    return int(found[0])
def jxa(code):
    return command(["osascript","-l","JavaScript","-e","var chrome=Application("+str(pid)+");"+code])
def evaluate(tab_id, code):
    script = ("var result=null;chrome.windows().forEach(w=>w.tabs().forEach(t=>{"
              "if(String(t.id())==="+json.dumps(str(tab_id))+"){"
              "if(!t.url().startsWith("+json.dumps(ORIGIN+"/evaluate/")+"))throw Error('评估页面已离开，停止');"
              "result=t.execute({javascript:"+json.dumps(code)+"});}}));"
              "if(result===null)throw Error('找不到目标评估标签页');result;")
    raw=jxa(script)
    if raw in ("", "null", "undefined"): raise RuntimeError("页面尚未可读")
    return json.loads(raw)

def read(tab_id):
    return evaluate(tab_id, """JSON.stringify({
      path:location.pathname,
      stopped:sessionStorage.getItem('ucas-eval-auto-stop')==='yes',
      pending:Array.from(document.querySelectorAll('a[href]')).filter(a=>a.textContent.trim()==='评估')
        .map(a=>new URL(a.href)).filter(u=>u.origin===location.origin&&u.pathname.startsWith('/evaluate/evaluate')).map(u=>u.pathname),
      entries:Array.from(document.querySelectorAll('a[href]')).filter(a=>a.textContent.trim()==='修改评估')
        .map(a=>new URL(a.href)).filter(u=>u.origin===location.origin).map(u=>u.pathname),
      captchaError:document.querySelector('#captchaType')?.value||'',
      report:document.querySelector('#ucas-helper-panel p')?.textContent||''
    })""")
def notify(tab_id,text):
    evaluate(tab_id,"(()=>{const p=document.querySelector('#ucas-helper-panel p');if(p)p.textContent="+json.dumps(text)+";return JSON.stringify(true);})()")
def navigate(tab_id,path):
    # 教师问卷比课程问卷多一个教师编号；真实教师页发现旧检查漏掉此段。
    if not re.fullmatch(r"/evaluate/(?:(?:course|teacher)/[0-9]+|evaluateCourse/[0-9]+/[0-9]+/[0-9]+|evaluateTeacher/[0-9]+/[0-9]+/[0-9]+/[0-9]+)",path):
        raise RuntimeError("异常评估路径，停止")
    evaluate(tab_id,"location.assign("+json.dumps(path)+");JSON.stringify(true)")
    time.sleep(1.2)
    deadline=time.monotonic()+20
    while time.monotonic()<deadline:
        info=read(tab_id)
        if info["path"]==path and info["report"]: return info
        time.sleep(.5)
    raise RuntimeError("目标问卷未加载")
def fill(tab_id):
    info=evaluate(tab_id,"""(()=>{
      const p=document.querySelector('#ucas-helper-panel');
      const b=p&&Array.from(p.querySelectorAll('button')).find(e=>e.textContent.startsWith('一键填写当前'));
      if(!b)throw Error('缺少统一填写按钮');b.click();
      const empty=Array.from(document.querySelectorAll('textarea')).filter(e=>!p.contains(e)).some(e=>e.value.trim().length<Math.max(0,e.minLength));
      return JSON.stringify({report:p.querySelector('p').textContent,empty:empty});
    })()""")
    if info["empty"] or not info["report"].startswith("已填写") or "另有 0 组" not in info["report"]:
        raise RuntimeError("问卷未完整填写："+info["report"])
def recognize_once(tab_id):
    image=evaluate(tab_id,"""(()=>{
      const img=document.querySelector('#adminValidateImg');
      if(!img||!img.complete||!img.naturalWidth)throw Error('验证码未加载');
      const canvas=document.createElement('canvas');canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;
      canvas.getContext('2d').drawImage(img,0,0,canvas.width,canvas.height);
      return JSON.stringify(canvas.toDataURL('image/png').split(',')[1]);
    })()""")
    output = command([OCR_PYTHON,"-c",OCR_CODE],image,timeout=90)
    value = json.loads(output.splitlines()[-1])["text"].replace(" ","")
    if not re.fullmatch(r"[A-Za-z0-9]{4}",value):
        raise RuntimeError("验证码识别格式不确定，未提交")
    return value
def recognize(tab_id):
    # 同一图的放大、分色仍无法稳定识别；只更换一次输入，两次不确定就停。
    try:
        return recognize_once(tab_id)
    except RuntimeError as error:
        if not str(error).startswith("验证码识别"):
            raise
        evaluate(tab_id,"""(()=>{
          const img=document.querySelector('#adminValidateImg');
          if(!img)throw Error('验证码图缺失');
          img.click();return JSON.stringify(true);
        })()""")
        time.sleep(1)
        return recognize_once(tab_id)
def submit(tab_id,code):
    evaluate(tab_id,"""(()=>{
      const input=document.querySelector('#adminValidateCode');
      const button=document.querySelector('#sb1');
      if(!input||!button)throw Error('学校保存入口已改变');
      input.value="""+json.dumps(code)+""";
      input.dispatchEvent(new Event('input',{bubbles:true}));
      button.click();return JSON.stringify(true);
    })()""")
    time.sleep(.5)
    evaluate(tab_id,"""(()=>{
      const boxes=Array.from(document.querySelectorAll('.jbox')).filter(e=>e.getClientRects().length&&e.textContent.includes('确认提交吗'));
      const buttons=boxes.flatMap(e=>Array.from(e.querySelectorAll('button'))).filter(e=>e.value==='ok'||e.textContent.trim()==='确定');
      if(buttons.length!==1)throw Error('未找到唯一的学校提交确认；停止');
      buttons[0].click();return JSON.stringify(true);
    })()""")
    time.sleep(1.5)
    result=read(tab_id)
    if result["captchaError"] in ("1","2"):
        raise RuntimeError("学校拒绝验证码，未保存；保留当前页，不自动重试")

def batch(tab_id,initial):
    match=re.fullmatch(r"/evaluate/(?:course|teacher|evaluateCourse|evaluateTeacher)/([0-9]+)(?:/[0-9]+){0,3}",initial["path"])
    if not match: raise RuntimeError("不能确认学期")
    semester=match.group(1); completed=0
    for kind in ["course","teacher"]:
        listing="/evaluate/"+kind+"/"+semester
        for _ in range(200):
            info=navigate(tab_id,listing)
            if info["stopped"]: raise RuntimeError("用户停止")
            paths=[p for p in info["pending"] if p.startswith("/evaluate/evaluate"+kind.title()+"/"+semester+"/")]
            if not paths: break
            target=paths[0]
            navigate(tab_id,target)
            if read(tab_id)["stopped"]: raise RuntimeError("用户停止")
            fill(tab_id)
            notify(tab_id,"本机正在识别验证码；识别成功后提交当前问卷。")
            code=recognize(tab_id)
            if read(tab_id)["stopped"]: raise RuntimeError("用户停止")
            submit(tab_id,code)
            # 从学校列表验证原入口确实成为“修改评估”，不根据离开表单判断成功。
            verified=navigate(tab_id,listing)
            if target not in verified["entries"]:
                raise RuntimeError("学校列表未确认保存成功，停止；请检查当前评价")
            completed+=1
            print("已核实保存",completed,"项",flush=True)
        else: raise RuntimeError("项目数超出预期，停止")
    notify(tab_id,"本学期课程和教师本页待评入口已清空，实际核实保存 "+str(completed)+" 项。其他分页未自动处理。")
    print("完成：核实保存",completed,"项",flush=True)

# 仅占用本机回环端口防止双开，不监听、不提供网络服务。
mutex=socket.socket()
try: mutex.bind(("127.0.0.1",39847))
except OSError: raise SystemExit("助手已经运行；请使用现有窗口。")
print("UCAS 本机识别助手已启动；在 Chrome 助手中点击自动完成。",flush=True)
last_error = None
while True:
    try:
        pid=chrome_pid()
        if pid is None:
            time.sleep(5)
            continue
        tabs=json.loads(jxa("""var out=[];chrome.windows().forEach(w=>w.tabs().forEach(t=>{
          if(t.url().startsWith('https://jwxk.ucas.ac.cn/evaluate/'))out.push(String(t.id()));
        }));JSON.stringify(out);"""))
        for tab_id in tabs:
            evaluate(tab_id,"""(()=>{const p=document.querySelector('#ucas-helper-panel');
              if(p)p.dataset.helperReady=String(Date.now());return JSON.stringify(true);})()""")
            requested=evaluate(tab_id,"""(()=>{
              const p=document.querySelector('#ucas-helper-panel');
              const requested=p?.dataset.autoRequested==='all';
              if(requested)p.dataset.autoRequested='';
              return JSON.stringify(requested);
            })()""")
            if requested:
                try: batch(tab_id,read(tab_id))
                except Exception as error:
                    print("停止：",str(error),flush=True)
                    try: notify(tab_id,"已停止："+str(error)+"。未自动重试。")
                    except Exception: pass
        last_error=None
    except KeyboardInterrupt: break
    except Exception as error:
        if str(error)!=last_error:
            print("等待页面：",str(error),flush=True)
            last_error=str(error)
    time.sleep(3)
PY

