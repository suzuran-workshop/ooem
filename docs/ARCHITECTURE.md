# ARCHITECTURE — BetterDictation

## 分层

```
┌──────────────────────────────────────────────┐
│ BetterDictation（AppKit 外壳）                │
│  AppDelegate   接线 + 权限轮询 + 绑定流程      │
│  StatusItem    菜单栏图标与菜单                │
│  HUDController 非激活浮层（底部中央）          │
│  DictationController  idle→listening→finishing │
└───────────────┬──────────────────────────────┘
                │ 依赖
┌───────────────▼──────────────────────────────┐
│ BetterDictationCore（可测逻辑）               │
│  HotkeyMonitor   CGEventTap(.cghidEventTap)  │
│  AudioCapture    AVAudioEngine → 16k/mono    │
│  IFlytekClient   WS 推流 + 结果累积           │
│  SpeechSegmenter 本地 VAD：说话/停顿切段     │
│  AudioRouter     会话轮换期间的 PCM 暂存     │
│  TextInjector    CGEvent Unicode 注入         │
│  Permissions     TCC 查询与引导                │
└──────────────────────────────────────────────┘
```

## 关键数据流

```
F5 down (CGEventTap, HID 层)
  → DictationController.toggle()
  → AudioCapture.start()         48k/1ch Float32（硬件）
      → AVAudioConverter         → 16k/1ch/Int16
      → Data(2 bytes × N)
  → AudioRouter.push()           有会话直送；轮换中先暂存
  → SpeechSegmenter.consume()    40ms 能量判定：speechStarted / commit
  → speechStarted：IFlytekClient.start() 建会话，补喂预卷音频
      → IFlytekClient.feed()     攒 1280 样本 → base64 → JSON 帧
  → commit（停顿 ≥ 250ms）：finish() 收尾本段
      → LiveTyper.update()       与「已注入内容」做差 → 只补增量
      → TextInjector.type(delta) CGEvent 逐段 Unicode 注入（边说边出现）
      → 等下一段语音再建会话
F5 down（第二次）
  → AudioCapture.stop()
  → IFlytekClient.finish()       status:2 尾帧 → 等服务端终稿（4s 超时兜底）
  → LiveTyper.update(终稿)       只补最后的增量，不重复已注入部分
```

## 模块职责

| 模块 | 职责 |
|------|------|
| `ASR/IFlytekConfig` | 端点常量、内置凭据、env 覆盖 |
| `ASR/IFlytekAuth` | RFC1123 日期 + HMAC-SHA256 签名 + 签名 URL |
| `ASR/IFlytekProtocol` | 80ms 分帧器、首帧/后续帧 JSON、下行帧解析 |
| `ASR/IFlytekClient` | URLSessionWebSocketTask 会话：推流、背压、结果累积、收尾超时 |
| `Audio/SpeechSegmenter` | 本地 VAD：40ms 能量 + 回滞阈值，输出 speechStarted / commit |
| `Audio/AudioRouter` | 会话轮换期间的 PCM 暂存与原子补喂，避免握手/收尾吞字 |
| `Audio/AudioCapture` | AVAudioEngine tap + AVAudioConverter；麦克风授权 |
| `Input/TextInjector` | 按 UTF-16 码元切块（不拆代理对）后逐段注入；退格回退 |
| `Input/LiveTyper` | 累积全文与已注入内容的差量规划（纯函数 `plan`，可单测） |
| `Hotkey/HotkeyMonitor` | HID 层事件 tap；键码与 `NX_KEYTYPE` 双路；吞事件；超时自愈 |
| `Hotkey/HotkeyBinding` | 绑定模型（Codable）+ 人类可读键名 |
| `Permissions` | 麦克风 / 辅助功能查询、系统设置深链 |
| `Support/Log` | stderr + `~/Library/Logs/BetterDictation.log` |

## 线程模型

- 事件 tap 回调运行在**主 RunLoop**（`CFRunLoopGetMain`），回调内只做判定与主线程派发。
- `IFlytekClient` 的状态全部收敛在私有串行队列；对外回调切回主线程。
- `AudioCapture` 的 tap 回调在音频渲染线程，只做转换与 `Data` 拷贝，不做阻塞操作。

## 权限模型

| 权限 | 用途 | 缺失表现 |
|------|------|----------|
| 麦克风 | 采集 | `AVAudioEngine.start()` 失败 / 静音 |
| 辅助功能 | 创建**可修改**的 CGEventTap；CGEvent 注入 | tap 创建失败（静默）、注入返回 false |

App 内置 2s 轮询：权限在运行期授予后自动恢复，不需要重启。
