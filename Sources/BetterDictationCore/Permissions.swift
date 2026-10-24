import Foundation
import AVFoundation
import ApplicationServices
import AppKit

public enum Permissions {

    public static var microphoneAuthorized: Bool {
        AudioCapture.microphoneStatus == .authorized
    }

    public static func requestMicrophone() async -> Bool {
        await AudioCapture.requestMicrophone()
    }

    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权引导（每个应用身份只弹一次）
    @discardableResult
    public static func promptAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
