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
