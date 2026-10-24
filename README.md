# BetterDictation

> 用 F5 唤起自己的流式听写：讯飞私有 ASR 直连，说完即插入光标，不碰系统听写、不经过任何云账号登录。

macOS 菜单栏小工具。按下唤醒键开始录音，再按一次结束；识别结果通过 `CGEvent` 直接打进当前焦点窗口（终端、浏览器、编辑器都行），全程不写剪贴板。

协议实现移植自 [`vow`](../vow) 的 `iflytek-asr`（同一套逆向结论与凭据），但这里是**宿主本机麦克风直连**，不再依赖手机或虚拟声卡。

## 功能

| 功能 | 说明 |
|------|------|
| F5 接管 | CGEventTap 在 HID 层监听，普通键 / 系统专用键（`NX_KEYTYPE`）双路识别，首次运行按一下即可绑定 |
| 流式识别 | 16kHz 单声道 → 80ms 分帧 → 讯飞 WS；分句边界实时回显中间结果 |
| 光标注入 | `CGEvent` Unicode 逐段注入，绕过输入法，不污染剪贴板 |
| 非侵入 | `LSUIElement` 菜单栏常驻，浮层不抢焦点，按 Esc 随时取消 |
| 零配置 | 凭据 base64 内置，`BETTERDICTATION_IFLYTEK_*` 可逐字段覆盖 |

## 环境

- macOS 14+，Apple Silicon（本机为 MacBook Air M4 / macOS 27.2）
- Command Line Tools（**不需要完整 Xcode**）

## 构建与安装

```bash
pnpm --version >/dev/null 2>&1 || true   # 与本项目无关，仅确认 shell 正常
swift build            # 编译
swift test             # 19 个单测（签名 golden 向量 / 分帧 / 下行解析 / 文本切块）
./scripts/build-app.sh # 产出 dist/BetterDictation.app 并 ad-hoc 签名
open dist/BetterDictation.app
```

安装到「应用程序」：

```bash
cp -R dist/BetterDictation.app /Applications/
```

## 首次运行（必做两件事）

1. **麦克风**：首次启动会弹系统授权，选「允许」。
2. **辅助功能**：系统设置 → 隐私与安全性 → **辅助功能** → 勾选 `BetterDictation`。
   授予后无需重启 App —— 内置 2 秒一次的重试轮询，权限一到就自动启动热键监听并进入绑定模式。

菜单栏出现麦克风图标后，屏幕底部会提示「绑定唤醒键」，此时**按一下 F5** 即完成绑定（也可以绑 F6 或任意键）。之后：

- 按 `F5` → 浮层显示「聆听中…」，开始推流
- 再按 `F5` → 显示「识别中…」，终稿自动打进光标处
- 按 `Esc` → 取消本次听写

## 常见问题

**按 F5 没反应？**
先看菜单栏菜单里的「权限：麦克风 ✅/❌　辅助功能 ✅/❌」。辅助功能未勾选时 CGEventTap 会静默失效，这是 macOS 的设计。

**F5 还是唤起了系统听写？**
系统听写已在「系统设置 → 键盘 → 听写」中关闭的话不会发生。若仍冲突，说明别处有残留的听写快捷键，检查同一页面的「键盘快捷键 → 听写」。

**重新构建后又要重新授权？**
ad-hoc 签名每次构建的 cdhash 都会变，TCC 会视作新程序。固定证书签名（或复用不再重编的产物）可避免；日常开发可接受。

**看不到浮层？**
浮层位于主屏底部中央、不抢焦点、不接收鼠标事件。多显示器时按 `NSScreen.main` 定位。

**日志在哪？**
菜单里「打开日志」，或 `~/Library/Logs/BetterDictation.log`。

## 目录

```
Sources/BetterDictationCore/   平台无关逻辑（ASR / 音频 / 注入 / 热键 / 权限）
Sources/BetterDictation/       AppKit 菜单栏外壳
Sources/BDSmoke/               端到端冒烟工具（真实音频 → 真实讯飞）
Tests/BetterDictationCoreTests/
scripts/build-app.sh           无 Xcode 的 .app 组装
docs/                          PRD / ARCHITECTURE / DECISIONS
```

## 已知边界

- 讯飞端点在**分句边界**才吐中间结果，不是逐字回声；HUD 的实时文本按句更新。
- 结束到终稿通常 < 1s，`finish` 以 6s 超时兜底（超时用已累积文本注入）。
- 依赖第三方私有协议，讯飞客户端升级可能更换凭据或字段（见 `docs/DECISIONS.md` D1）。
