# BetterDictation

> F5 唤起自己的流式听写：讯飞私有 ASR 直连，**边说边打进输入框**，不碰系统听写、不登录任何账号。

macOS 菜单栏小工具。按下唤醒键开始录音，识别结果在说话过程中就逐段注入当前焦点窗口；再按一次结束并补齐终稿。全程不写剪贴板、不弹浮层、不抢焦点。

协议实现移植自 [`vow`](../vow) 的 `iflytek-asr`，但这里是**宿主本机麦克风直连**，不再依赖手机或虚拟声卡。

![build](https://github.com/wpy030414/BetterDictation/actions/workflows/build.yml/badge.svg)

## 功能

| 功能 | 说明 |
|------|------|
| F5 接管 | CGEventTap 于 HID 层监听，普通键 / 系统专用键（`NX_KEYTYPE`）双路识别，首次运行按一下即可绑定 |
| 边识别边打字 | 分句边界一到就直接写入焦点窗口；服务端修正时自动回退到公共前缀重打 |
| 零打扰 | 听写过程**没有任何浮层**，状态只在菜单栏图标上体现 |
| 光标注入 | `CGEvent` Unicode 逐段注入，绕过输入法，不污染剪贴板 |
| 开机自启 | 菜单一键开关；优先 `SMAppService`，被拒则回退 `LaunchAgents` |
| 零配置 | 凭据 base64 内置，`BETTERDICTATION_IFLYTEK_*` 可逐字段覆盖 |

## 环境

- macOS 14+，Apple Silicon（本机为 MacBook Air M4 / macOS 27.2）
- Command Line Tools（**不需要完整 Xcode**）

## 构建与安装

```bash
swift build            # 编译
swift test             # 25 个单测
./scripts/build-app.sh # 产出 dist/BetterDictation.app 并 ad-hoc 签名
```

想要「装好就能用、后台运行、不占终端」：

```bash
make install           # 构建 → 复制到 /Applications → open 后台启动
```

`open` 会把进程交给 launchd，命令立刻返回，终端窗口可以直接关掉。

## 首次运行（必做两件事）

1. **麦克风**：首次启动会弹系统授权，选「允许」。
2. **辅助功能**：系统设置 → 隐私与安全性 → **辅助功能** → 勾选 `BetterDictation`。
   授予后无需重启 App —— 内置 2 秒一次的重试轮询，权限一到就自动启动热键监听并进入绑定模式。

菜单栏出现 **BT + 麦克风** 图标后，屏幕底部会提示「绑定唤醒键」，此时**按一下 F5** 即完成绑定。之后：

- 按 `F5` → 菜单栏图标变成实心麦克风，开始推流；说话时文本**直接出现在输入框里**
- 再按 `F5` → 图标变波形，补齐终稿后回到就绪
- 按 `Esc` → 取消本次听写（已经打进去的字保留）

## 从 Release 下载

CI 产出的 `.zip` 已做 ad-hoc 签名，但会被 Gatekeeper 打上隔离属性：

```bash
unzip BetterDictation-macos-arm64.zip
xattr -dr com.apple.quarantine BetterDictation.app
mv BetterDictation.app /Applications/
open /Applications/BetterDictation.app
```

## 常见问题

**按 F5 没反应？**
先看菜单栏菜单里的「权限：麦克风 ✅/❌　辅助功能 ✅/❌」。辅助功能未勾选时 CGEventTap 会静默失效，这是 macOS 的设计。

**说话时字打到别的窗口去了？**
注入目标是「当前焦点窗口」，和系统听写一致。开始听写前先把光标放好。

**重新构建后又要重新授权？**
ad-hoc 签名每次构建的 cdhash 都会变，TCC 会视作新程序。装到 `/Applications` 并固定使用同一份产物可减少打扰；正式分发应换 Developer ID 签名。

**开机自启没生效？**
菜单里的勾选状态来自实际探测。若 `SMAppService` 被拒会回退到 `~/Library/LaunchAgents/io.xrl.BetterDictation.plist`；日志会写明走了哪条路。

**日志在哪？**
菜单里「打开日志」，或 `~/Library/Logs/BetterDictation.log`。

## 目录

```
Sources/BetterDictationCore/   平台无关逻辑（ASR / 音频 / 注入 / 热键 / 权限）
Sources/BetterDictation/       AppKit 菜单栏外壳（图标 / 菜单 / 开机自启）
Sources/BDSmoke/               端到端冒烟工具（真实音频 → 真实讯飞）
Tests/BetterDictationCoreTests/
scripts/build-app.sh           无 Xcode 的 .app 组装
scripts/install.sh             安装到 /Applications 并后台启动
.github/workflows/build.yml    CI：测试 → 构建 → 打包 → tag 发 Release
docs/                          PRD / ARCHITECTURE / DECISIONS
```

## 已知边界

- 讯飞端点在**分句边界**才吐中间结果，不是逐字回声；因此输入框里的文字按句出现。
- 边打字边识别意味着「用户中途移动光标」会让后续文字落到新位置 —— 与系统听写相同的固有约束。
- 结束到终稿通常 < 1s，`finish` 以 6s 超时兜底。
- 依赖第三方私有协议，讯飞客户端升级可能更换凭据或字段（见 `docs/DECISIONS.md` D1）。
