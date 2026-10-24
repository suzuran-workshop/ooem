# AGENTS.md — BetterDictation

## 项目定位

macOS 菜单栏听写工具：F5 唤起 → 本机麦克风 → 讯飞私有 ASR 流式转写 → `CGEvent` 注入焦点窗口。

## 架构约束

- **平台无关逻辑一律放 `BetterDictationCore`**，AppKit 外壳只做接线。新增可测逻辑不要写进 `Sources/BetterDictation/`。
- 音频链路固定为 **16kHz / 单声道 / PCM16LE**；分帧固定 **80ms（1280 样本）**，这是讯飞实况节奏，改动前先看 `docs/DECISIONS.md`。
- 文本注入只走 `CGEvent` Unicode 路径：不写 `NSPasteboard`（会污染用户剪贴板、与剪贴板管理器冲突），不使用 AppleScript keystroke（依赖 Apple Events 且慢）。
- 热键监听在 `.cghidEventTap`，必须处理 `tapDisabledByTimeout` 重新启用，否则会「用着用着失效」。

## 开发习惯

- 构建：`swift build`；测试：`swift test`（swift-testing，**不支持 XCTest** —— 本机只有 Command Line Tools）。
- 打包：`./scripts/build-app.sh`（ad-hoc 签名，产物在 `dist/`，不入库）。
- 新增 ASR 协议字段时，先跑 `swift run -c release bd-smoke <pcm16le.raw> --realtime` 验证真实端点，再改单测。
- 调试下行帧：`IFLYTEK_DEBUG=1` 会把原始 JSON 打到日志。

## 验收标准

1. `swift test` 全绿；
2. `bd-smoke` 用真实语音跑通并拿到正确终稿；
3. `scripts/build-app.sh` 产物 `codesign --verify` 通过；
4. 真机 F5 → 说话 → 再按 F5 → 文本出现在焦点窗口。

## 文档

改动涉及协议、权限模型、注入策略时，同步更新 `docs/DECISIONS.md`（追加决策记录，不要改写历史条目）。
