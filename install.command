#!/bin/zsh
# macOS：安装本机评教后台助手。--check 只检查，不安装、不提交评价。
# 可用 UCAS_OCR_PYTHON 指定已装 ddddocr、onnxruntime 的 Python。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
package_dir="${0:A:h}"
install_dir="$HOME/.local/share/ucas-chrome-helper"
agent_path="$HOME/Library/LaunchAgents/local.ucas-evaluation.plist"
check_only=0
if [[ "${1:-}" == --check ]]; then
    check_only=1
elif [[ $# -gt 0 ]]; then
    print -u2 '用法：install.command [--check]'; exit 1
fi
[[ "$(uname -s)" == Darwin ]] || { print -u2 '此安装器仅适用于 macOS。'; exit 1; }
for source_file in ucas_evaluation.command ucas_evaluation.user.js; do
    [[ -s "$package_dir/$source_file" ]] || { print -u2 "缺少 $source_file，请保留完整分享文件夹。"; exit 1; }
done
/bin/zsh -n "$package_dir/ucas_evaluation.command"
ocr_python="${UCAS_OCR_PYTHON:-}"
if [[ -z "$ocr_python" && -x "$HOME/UCAS-Desktop/.venv/bin/python" ]]; then
    ocr_python="$HOME/UCAS-Desktop/.venv/bin/python"
fi
if [[ -n "$ocr_python" ]]; then
    [[ -x "$ocr_python" ]] || { print -u2 '指定的 Python 不可执行。'; exit 1; }
    "$ocr_python" -c 'import ddddocr, onnxruntime'
else
    base_python="$(command -v python3.11 || true)"
    [[ -n "$base_python" ]] || { print -u2 '请先安装 Python 3.11，或按 README 指定已有 OCR 环境。'; exit 1; }
    ocr_python="$install_dir/venv/bin/python"
fi
if (( check_only )); then
    print '检查运行成功；未安装、未启动后台服务、未操作评估页。'
    [[ -x "$ocr_python" ]] || print '正式安装时将创建独立 Python 环境并下载识别依赖。'
    exit 0
fi
if [[ -e "$agent_path" || -e "$install_dir/ucas_evaluation.command" ]] || /bin/launchctl print "gui/$(id -u)/local.ucas-evaluation" >/dev/null 2>&1; then
    print -u2 '已有同名助手，停止安装以免覆盖。请按 README 核对现有配置。'; exit 1
fi
mkdir -p "$install_dir" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
if [[ ! -x "$ocr_python" ]]; then
    "$base_python" -m venv "$install_dir/venv"
    "$ocr_python" -m pip install 'ddddocr==1.5.6' 'onnxruntime==1.19.2' 'numpy<2' 'opencv-python-headless==4.10.0.84'
fi
"$ocr_python" -c 'import ddddocr, onnxruntime; ddddocr.DdddOcr(show_ad=False)'
cp "$package_dir/ucas_evaluation.command" "$install_dir/ucas_evaluation.command"
chmod 700 "$install_dir/ucas_evaluation.command"
"$ocr_python" - "$install_dir" "$agent_path" <<'PY'
import pathlib, plistlib, sys
root, agent = map(pathlib.Path, sys.argv[1:])
home = pathlib.Path.home()
python = sys.executable
data = {
    'Label': 'local.ucas-evaluation',
    'ProgramArguments': ['/bin/zsh', str(root/'ucas_evaluation.command')],
    'EnvironmentVariables': {'UCAS_OCR_PYTHON': python, 'UCAS_RUNNER_PYTHON': python},
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 30,
    'ProcessType': 'Background',
    'StandardOutPath': str(home/'Library/Logs/ucas-evaluation.log'),
    'StandardErrorPath': str(home/'Library/Logs/ucas-evaluation-error.log'),
}
with agent.open('wb') as handle:
    plistlib.dump(data, handle)
agent.chmod(0o600)
PY
/usr/bin/plutil -lint "$agent_path"
/bin/launchctl bootstrap "gui/$(id -u)" "$agent_path"
/bin/launchctl print "gui/$(id -u)/local.ucas-evaluation" >/dev/null
print '后台服务已加载。请继续 README 中的 Chrome 权限及油猴脚本配置。'
print '以后登录 Mac 后自动待命，不需要双击辅助文件或保留终端。'
