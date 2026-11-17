// ==UserScript==
// @name         国科大SEP自动评教（2026最新适配版）
// @namespace    http://tampermonkey.net/
// @license      MIT
// @version      2.3
// @description  同一Chrome入口连续填写待评问卷；核对答案及验证码后用学校保存按钮提交。
// @match        https://jwxk.ucas.ac.cn/evaluate/*
// @grant        none
// @run-at       document-end
// ==/UserScript==
(function () {
    'use strict';
    if (window.top !== window.self || document.getElementById('ucas-helper-panel')) return;
    const key = 'ucas-evaluation-helper-v21';
    const batchKey = key + '-batch';
    const path = location.pathname;
    const isTeacher = path.includes('/evaluateTeacher/');
    const isForm = path.includes('/evaluateCourse/') || isTeacher;
    const kind = isTeacher || path.includes('/teacher/') ? 'teacher' : 'course';
    const defaults = kind === 'teacher'
        ? ['老师授课认真负责，重点突出，讲解清晰且注重课堂交流。', '希望继续保持理论与实际案例相结合的教学方式。']
        : ['老师讲解清晰，课程内容充实，理论与实际案例结合紧密。', '希望继续增加案例讨论与课程资料，便于课后理解和复习。', '8小时',
           '参与课程之前，我已对该学科领域的相关知识有较为浓厚的兴趣。',
           '我按课程要求参与课堂学习和讨论，并认真完成相关学习任务。'];
    const panel = document.createElement('section');
    panel.id = 'ucas-helper-panel';
    panel.style.cssText = 'position:fixed;right:18px;top:90px;z-index:2147483647;width:340px;max-height:80vh;overflow:auto;background:white;color:#222;border:2px solid #2865ae;border-radius:8px;padding:14px;box-shadow:0 4px 18px #0003;font:14px/1.5 sans-serif;text-align:left';
    const heading = document.createElement('strong');
    heading.textContent = 'SEP 统一评教助手 2.3';
    panel.append(heading);
    const status = document.createElement('p');
    panel.append(status);
    function message(text) { status.textContent = text; }
    function button(text, action) {
        const b = document.createElement('button');
        b.type = 'button'; b.textContent = text;
        b.style.cssText = 'margin:5px 5px 5px 0;padding:7px;cursor:pointer';
        b.onclick = () => { try { action(); } catch (e) { sessionStorage.removeItem(batchKey); message('已停止：' + e.message); } };
        panel.append(b); return b;
    }
    function state() {
        try { return JSON.parse(sessionStorage.getItem(batchKey) || 'null'); }
        catch (_) { sessionStorage.removeItem(batchKey); return null; }
    }
    button('停止连续处理', () => { sessionStorage.removeItem(batchKey); message('已停止连续处理；当前答案未清除。'); });
    document.body.append(panel);
    button('自动完成本学期课程和教师评估', () => {
        if (!confirm('将按当前统一模板提交本学期所有待评课程和教师问卷：评分选非常满意；课程教室 A、修读原因全选。验证码由本机识别；错误时停止。是否开始？')) return;
        sessionStorage.removeItem(batchKey);
        panel.dataset.stopRequested = ''; sessionStorage.removeItem('ucas-eval-auto-stop');
        panel.dataset.autoRequested = 'all';
        message('等待本机识别助手接入；尚未提交。');
    });
    panel.querySelector('button').addEventListener('click', () => { panel.dataset.stopRequested = 'yes'; sessionStorage.setItem('ucas-eval-auto-stop', 'yes'); });
    const semester = path.split('/')[3];
    const listPath = '/evaluate/' + kind + '/' + semester;
    if (!isForm) {
        if (!path.startsWith('/evaluate/course/') && !path.startsWith('/evaluate/teacher/')) {
            message('请从学校菜单进入本学期课程或教师评估列表。'); return;
        }
        const pending = Array.from(document.querySelectorAll('a[href]')).filter(a => {
            const u = new URL(a.href);
            return a.textContent.trim() === '评估' && u.origin === location.origin &&
                u.pathname.startsWith('/evaluate/evaluate' + (kind === 'teacher' ? 'Teacher' : 'Course') + '/' + semester + '/');
        });
        message('本页待评：' + pending.length + ' 项。连续模式会填写下一份问卷；请逐份核对、输入验证码并点击学校保存。已有评价不会打开。');
        function next() {
            if (!pending.length) { sessionStorage.removeItem(batchKey); message('本页没有待评入口；其他分页及另一类问卷需另行检查。'); return; }
            const s = state() || {};
            s.kind = kind; s.semester = semester; s.path = new URL(pending[0].href).pathname; s.submitted = false;
            sessionStorage.setItem(batchKey, JSON.stringify(s));
            location.assign(pending[0].href);
        }
        button('开始连续填写待评项目', next);
        const s = state();
        if (s && s.kind === kind && s.semester === semester) {
            const oldEntry = Array.from(document.querySelectorAll('a[href]')).find(a => new URL(a.href).pathname === s.path);
            if (s.submitted && oldEntry && oldEntry.textContent.trim() === '修改评估') {
                message('上一项已变为“修改评估”，正在打开下一项。');
                setTimeout(next, 1200);
            } else {
                sessionStorage.removeItem(batchKey);
                message('已停止：未核到上一项由“评估”变为“修改评估”。请先检查学校提交结果。');
            }
        }
        return;
    }
    const note = document.createElement('p');
    note.textContent = '以下为可修改的草稿，评分默认最左侧“非常符合／非常满意”。请按实际体验核对；验证码与提交由你完成。';
    panel.append(note);
    const drafts = defaults.map((text, i) => {
        const label = document.createElement('label');
        label.textContent = '主观题 ' + (i + 1);
        const field = document.createElement('textarea');
        field.value = text; field.rows = 2; field.style.cssText = 'display:block;width:96%;margin:4px 0';
        label.append(field); panel.append(label); return field;
    });
    function fill() {
        // 旧脚本逐行选首项后又按 value=1 扫描，会把评分改到最右列。
        // 本版按 name 分组，只处理 5、4、3、2、1 的评分组，并核对表头列。
        const radios = Array.from(document.querySelectorAll('input[type=radio]'));
        const names = Array.from(new Set(radios.map(e => e.name)));
        const targets = [];
        for (const name of names) {
            const group = radios.filter(e => e.name === name);
            if (!name.startsWith('item_')) continue;
            if (group.length !== 5 || group.map(e => e.value).sort().join(',') !== '1,2,3,4,5') throw Error('评分结构改变，未填写。');
            const target = group.find(e => e.value === '5');
            const cell = target.closest('td');
            const table = target.closest('table');
            const header = Array.from(table.rows).find(r => r.textContent.includes('非常满意'));
            if (!cell || !header || !header.cells[cell.cellIndex]?.textContent.includes('非常满意')) throw Error('无法确认满分对应列，未填写。');
            targets.push(target);
        }
        if (!targets.length) throw Error('未找到已确认的评分题。');
        const fields = Array.from(document.querySelectorAll('textarea')).filter(e => !panel.contains(e));
        if (fields.length !== drafts.length) throw Error('主观题数量改变，未填写。');
        fields.forEach((e, i) => {
            if (drafts[i].value.trim().length < Math.max(0, e.minLength)) throw Error('主观题 ' + (i + 1) + ' 字数不足。');
        });
        targets.forEach(e => e.click());
        fields.forEach((e, i) => {
            e.value = drafts[i].value.trim();
            e.dispatchEvent(new Event('input', { bubbles: true }));
            e.dispatchEvent(new Event('change', { bubbles: true }));
        });
        // 2026-11-17 用户指定教室 A、修读原因 A-F 全选；按文字定位空 value 的选项。
        if (!isTeacher) {
            const room = radios.filter(e => e.classList.contains('radio') && e.parentElement.textContent.trim().startsWith('A.教室大小合适'));
            const reasons = Array.from(document.querySelectorAll('input.checkbox'));
            if (room.length !== 1 || reasons.length !== 6) throw Error('教室或修读原因结构改变，请核对。');
            room[0].click();
            reasons.forEach(e => { if (!e.checked) e.click(); });
        }
        const incomplete = names.filter(name => !radios.some(e => e.name === name && e.checked)).length;
        message('已填写 ' + targets.length + ' 组评分和 ' + fields.length + ' 道主观题。另有 ' + incomplete + ' 组单选未填；教室 A、修读原因全选。未提交。');
        const captcha = document.querySelector('input[name=adminValidateCode]');
        if (captcha) captcha.scrollIntoView({ block: 'center' });
    }
    button('一键填写当前问卷（不提交）', fill);
    button('返回本学期列表', () => { sessionStorage.removeItem(batchKey); location.assign(listPath); });
    message('助手已加载。修改草稿后点击一键填写；教室选 A、修读原因全选；请核对后保存。');
    const s = state();
    if (s && s.path === path && s.kind === kind) {
        try { fill(); } catch (e) { sessionStorage.removeItem(batchKey); message('已停止：' + e.message); }
    }
    // 学校验证码在表单外，由 #sb1 点击事件打包提交；监听按钮，并用列表状态核实保存。
    const saveButton = document.querySelector('#sb1');
    if (saveButton) saveButton.addEventListener('click', () => {
        const s = state(); if (s && s.path === path) { s.submitted = true; sessionStorage.setItem(batchKey, JSON.stringify(s)); }
    }, true);
})();
