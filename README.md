# 国科大 Chrome 统一评教助手（Mac 分享包）

安装一次，以后在日常 Google Chrome 的学校评估页点击“自动完成本学期课程和教师评估”，核对确认框后开始。助手在后台运行，不用每次打开辅助文件或保留终端窗口。

本包适用于 macOS 和桌面版 Google Chrome，不适用于 Windows。学校登录由本人完成；不包含账号、密码、登录状态、验证码图片或识别模型。

## 一次性配置

1. 在 Chrome 安装 Tampermonkey（油猴：运行网页用户脚本的扩展）。在 `chrome://extensions/` 打开它的详情，开启“允许用户脚本”；若浏览器要求开启开发者模式，按界面提示操作。
2. 点 Chrome 窗口，在屏幕最上方菜单栏开启 **View（显示）→ Developer（开发者）→ Allow JavaScript from Apple Events（允许来自 Apple 事件的 JavaScript）**。这不是右上角三个点菜单。
3. 油猴菜单 → 管理面板 → 实用工具 → 导入文件，选择同文件夹的 `ucas_evaluation.user.js` 并确认安装。已有同名旧脚本时更新该脚本，避免两个版本同时启用。也可新建脚本，用本文件完整内容替换模板并保存。
4. 双击 `install.command`。已有 `~/UCAS-Desktop/.venv/bin/python` 且安装了识别依赖时复用它；否则需要先准备 Python 3.11，安装器再建立独立环境，联网安装识别依赖。首次安装需要等待。安装成功显示“后台服务已加载”。此时可以关闭终端。
5. 首次出现 macOS 自动化授权提示时，允许此助手使用 Google Chrome；若禁止了，到系统设置 → 隐私与安全性 → 自动化核对相应权限。授权归属和提示文字可能因 Python 安装方式不同而变化。
6. 自行登录 SEP，从选课系统进入本学期课程或教师评估列表（`https://jwxk.ucas.ac.cn/evaluate/…`），刷新后确认右侧出现“SEP 统一评教助手 2.3”。

如果 Finder 提示没有执行权限，可在终端执行（路径按实际存放位置调整）：

```zsh
chmod +x "$HOME/Downloads/ucas_chrome_helper/install.command"
"$HOME/Downloads/ucas_chrome_helper/install.command"
```

若已有其他独立 Python 环境，可显式指定，安装器会先检查依赖，不修改该环境：

```zsh
UCAS_OCR_PYTHON="/你的环境/bin/python" "$HOME/Downloads/ucas_chrome_helper/install.command"
```

## 先核对答案，再开始

此版本复用原使用者确认过的模板：评分为最左侧“非常满意”，教室 A（大小合适），修读原因 A–F 全选；课程投入时间为“8小时”，主观题使用脚本里的中文草稿。**这些选择不代表其他人的实际体验。** 分享给他人时，应先在油猴编辑器修改 `defaults`、评分选择及教室/修读原因逻辑，再保存。自动模式每打开一份问卷都会重新采用脚本模板；页面临时编辑的草稿不会自动带到下一份。

先在一份问卷点击“一键填写当前问卷（不提交）”，逐项核对。确认模板适合所有待评课程后，再点击“自动完成本学期课程和教师评估”并确认。它会实际提交，自动识别验证码、切换课程和教师问卷，并用学校列表上的“修改评估”核实保存；已有评价跳过。

“开始连续填写待评项目”是保留的手动模式，需要自己核对验证码并保存。面板里“验证码与提交由你完成”的说明针对这一手动模式；自动模式以按钮确认框为准。

点击“停止连续处理”停止后续处理，已提交的评价不会撤销。遇到识别失败、学期或题目结构不明、学校拒绝验证码、未核实保存时会停止；先看提示，不要反复点击。验证码识别不保证每次成功，也不绕过学校校验。

## 后台位置与排查

- 程序：`~/.local/share/ucas-chrome-helper/ucas_evaluation.command`
- 独立识别环境（需要新建时）：`~/.local/share/ucas-chrome-helper/venv/`
- 登录后台任务：`~/Library/LaunchAgents/local.ucas-evaluation.plist`
- 日志：`~/Library/Logs/ucas-evaluation.log`、`ucas-evaluation-error.log`

程序只对现有日常 Chrome 的学校评估页执行操作；Chrome 没开时等待，不会为此自动打开浏览器。它不开放网络服务。运行时须保持 Mac 登录、联网和 Chrome 可用。不要同时运行两份后台助手；已有同名配置时安装器会停止，不覆盖。

只检查安装前提（不会安装或提交）：

```zsh
"$HOME/Downloads/ucas_chrome_helper/install.command" --check
```

停止后台服务：

```zsh
launchctl bootout "gui/$(id -u)/local.ucas-evaluation"
```

重新加载：

```zsh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.ucas-evaluation.plist"
```

不再使用时先停止服务，再在油猴禁用脚本；需要彻底移除时，自行删除上列程序、plist 和日志，并关闭 Chrome 的 Apple 事件 JavaScript 权限。其他程序复用的 Python 环境应保留。

## 验证范围（2026-11-17）

原使用者的 MacBook Air 已用这套脚本及现有 ddddocr 1.5.6、onnxruntime 1.19.2 完成真实课程、教师评价，学校两张列表待评均为零。该机后台任务与页面连接检查运行成功。本分享包导出的是同一份已安装的 2.3 脚本。

分享包的语法和只读安装检查在该机运行成功；其他 Mac 的全新依赖安装、自动化首次授权、重新登录后的启动及新学期页面均未做实际验证。学校改版后须重新核对题目，不能只凭按钮出现判断填写正确。
