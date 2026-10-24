# DECISIONS — BetterDictation

## D1：复用 vow 的讯飞私有协议与凭据

**背景**：vow 项目已完成对讯飞输入法客户端的协议逆向，并用真实会话验证（签名 golden 向量 + 96 帧音频回放逐字一致）。

**决策**：直接移植 `iflytek-asr.ts` 的协议实现，凭据 base64 内置于 `IFlytekConfig`，env 可逐字段覆盖。

**代价**：依赖第三方私有接口，源客户端升级可能更换凭据/字段；凭据解析中。

**替代方案**：官方开放平台需要实名注册与额度购买，与「开箱即用」的产品目标冲突。

## D2：`aue: "raw"` 直发 PCM16

讯飞实况客户端用 opus-wb 容器，但已验证 `encoding:"raw"` 直发 PCM16LE@16k 被服务端接受且转写一致。省掉 Opus 编码依赖。

## D3：用 URLSessionWebSocketTask，不手写 WebSocket

服务端不回显 `Sec-WebSocket-Protocol`，Node `ws` 严格协商会报错。实测 `URLSession` 允许缺失回显，且自定义头（`Origin` / `Sec-WebSocket-Protocol`）能完整透传 —— 直接用系统实现，省掉握手/掩码/分片的自研风险。

## D4：F5 接管用 CGEventTap，不依赖 Karabiner

Karabiner 的 DriverKit 虚拟设备接管层级更低、更稳，但需要安装系统扩展与重启。本项目的目标受众只想要一个自带能力的 App，因此选择 `.cghidEventTap`（`.headInsertEventTap` + `.defaultTap`）：

- 需要在 HID 层（session 层可能已看不到专用功能键）；
- 需要辅助功能权限（与文本注入共用同一权限，不额外增加成本）；
- 必须处理 `tapDisabledByTimeout` 自动重启用。

**绑定是自学习的**：不硬编码「F5 = keyCode 96」，首次运行让用户按一下，把真实事件形态（普通键 / `NX_KEYTYPE`）存进 `UserDefaults`。这样无论 Apple 把听写键实现成键盘页还是系统定义事件，都能正确接管。

## D5：切换式而非按住式

系统听写的 F5 是切换式（按一下开、再按一下关），用户已有肌肉记忆。按住说话在 5 秒以上的长句会手酸。因此采用切换式，Esc 取消作为逃生口。

## D6：不写剪贴板

剪贴板注入（设置 → `Cmd+V` → 恢复）更快，但会污染剪贴板、与剪贴板管理器冲突，中文输入法候选框偶尔会吞掉粘贴。`CGEvent` Unicode 注入逐段发送，牺牲一点速度换确定性。

## D7：测试用 swift-testing

本机只有 Command Line Tools，`XCTest` 模块不可用（`unable to resolve module dependency: 'XCTest'`），而 `Testing.framework` 随 CLT 提供。测试目标统一用 `@Test` / `#expect`。

## D8：不做 Xcode 工程

无 Xcode 环境下 `xcodebuild` 不可用；SwiftPM + 手写 `Info.plist` + `codesign --sign -` 足以产出可运行的 `.app`。代价是每次重编 cdhash 变化会导致 TCC 重新授权（见 README）。

## D9：边识别边注入，不在 GUI 里回显

系统听写的交互是「字直接出现在输入框」，用户已经习惯。原实现把中间结果画在浮层里，既突兀又多余。

**做法**：`LiveTyper` 把服务端的累积全文与本地「已注入字符串」做差：
- 累积文本以已注入内容为前缀 → 只输入新增部分（主流路径）；
- 否则（服务端修正）→ 回退到公共前缀，发 N 次退格后重打剩余部分。

**代价**：如果用户中途把光标移走，后续文字会落到新位置；这与系统听写一致，属于固有约束。

## D10：听写过程零浮层

只在「绑定按键」和「错误提示」时显示浮层，且强制深色外观（`NSAppearance(.darkAqua)`）—— 避免浅色模式下变成一块白色圆角。听写状态完全通过菜单栏图标表达（BT + 麦克风 / 实心麦克风 / 波形）。

## D11：开机自启优先 SMAppService，失败回退 LaunchAgent

`SMAppService.mainApp` 要求可信签名与稳定位置；ad-hoc 签名、或从 `dist/` 直接运行时可能被拒。因此注册失败时自动写 `~/Library/LaunchAgents/io.xrl.BetterDictation.plist`（`RunAtLoad`）。两条路径都会写日志，菜单勾选状态来自实际探测。

## D12：CI 在 macOS runner 上产出 arm64 包

`.github/workflows/build.yml`：`swift test` → `scripts/build-app.sh` → `ditto` 打包 → 上传 artifact；打 `v*` tag 时自动建 Release。GitHub 的 `macos-15` runner 是 Apple Silicon，因此产物天然 arm64。

ad-hoc 签名的包分发后会被 Gatekeeper 隔离，README 给出了 `xattr -dr com.apple.quarantine` 的处理步骤。

## D13：Release 由分支 push 触发，不再依赖 tag

**背景**：原先 CI 只在 `v*` tag 上发 Release，日常 push 只产出 artifact。实际使用中经常忘记打 tag，下载页长期落后于 main。

**决策**：`.github/workflows/build.yml` 监听 `main` / `master` 的 push（以及手动 dispatch），每次构建成功后用代码里的版本号生成 tag（`v<marketing>`）并创建 Release；同一版本重复 push 时更新已有 Release 的资产。PR 只跑测试与构建，不发 Release。

**代价**：同一版本号下的多次 push 会覆盖同一个 Release 的资产，tag 停留在该版本首次发布的提交；追溯具体构建靠 Release 名称里的短 SHA。

**替代方案**：维护一个滚动 `latest` Release 原地覆盖。tag 会停留在首次提交、无法保留历史构建，故不采用。

## D14：本地 VAD 分段 + 会话轮换

**背景**：实测 `100ime-iat-api.xfyun.cn/v2/iat` 在 `status:1` 推流期间**不返回任何中间结果**，只有服务端 VAD 收尾（或本端发 `status:2`）时一次性返回整段文字；把 `vad_speech_tail` 调到 300–500ms 也一样。因此 D9 虽然接了 `onPartial`，真实表现仍是「全部说完才出字」。

**决策**：在客户端做 VAD（`SpeechSegmenter`）：

- 40ms 帧能量 + 回滞阈值判定说话 / 静音；
- 检测到语音才建立 ASR 会话，长停顿不再空转连接；
- 停顿 ≥ 250ms 即收尾当前会话，拿到文字立刻注入，再等下一段语音建新会话；
- 连续说话 12s 后放宽切段条件：不再等 250ms 停顿，遇到第一个 80ms 词间间隙就收尾；若一直没有间隙，整段继续累积，直到下一次停顿或按停止 —— **不丢弃任何音频**，只是出字延迟；
- `AudioRouter` 在收尾 / 握手期间缓存 PCM，新会话就绪后原样补喂，避免吞字；
- 每段文本仍经 `LiveTyper` 与已注入内容做差，保证不重复、可回退。

**代价**：文字以「短语」为粒度出现，延迟约等于停顿阈值 + 一次会话收尾（实测 0.3–0.8s）；阈值过小会把一句话切碎，过大又回到高延迟。阈值集中在 `SpeechSegmenter.Config`，可单测调整。

## D15：版本号以 Swift 代码为单一来源

**背景**：D13 的版本号从 `Info.plist` 读取，改版本要动资源文件；代码里也看不到当前版本，运行时无法确认装的是哪一版。

**决策**：`AppVersion.marketing`（`Sources/BetterDictationCore/Support/AppVersion.swift`）是唯一来源：

- `scripts/version.sh` 解析这一行，`scripts/build-app.sh` 与 CI 用它写 `CFBundleShortVersionString`；
- CI 的 Release tag 为 `v<marketing>`，`CFBundleVersion` 保持 `Info.plist` 里的值；
- 菜单与 tooltip 显示 `marketing`，装的是哪一版一眼可见。

**代价**：要发新版本必须推进代码里的 `marketing`，只改 tag 或 Release 名称不会改变程序里的版本号。

**替代方案**：用 `Info.plist` 或 `VERSION` 文件作源。资源文件在代码里不可见，运行时也拿不到营销版本，故不采用。
