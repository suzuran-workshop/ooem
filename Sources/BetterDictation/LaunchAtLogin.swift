import Foundation
import ServiceManagement
import BetterDictationCore

/// 开机自启：优先 `SMAppService`，失败时回退到 `~/Library/LaunchAgents`。
/// ad-hoc 签名或非 /Applications 位置可能让 SMAppService 注册被拒，回退路径保证可用。
enum LaunchAtLogin {

    static let agentLabel = "io.xrl.BetterDictation"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                log("开机自启：SMAppService 注册成功")
                return
            } catch {
                log("SMAppService 注册失败（\(error.localizedDescription)），回退 LaunchAgent")
                try installAgent()
            }
        } else {
            try? SMAppService.mainApp.unregister()
            removeAgent()
            log("开机自启：已关闭")
        }
    }

    private static func installAgent() throws {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: agentURL, options: .atomic)
        log("开机自启：已写入 LaunchAgent \(agentURL.path)")
    }

    private static func removeAgent() {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return }
        try? FileManager.default.removeItem(at: agentURL)
        log("开机自启：已移除 LaunchAgent")
    }
}
