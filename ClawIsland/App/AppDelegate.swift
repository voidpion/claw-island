import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindowController: NotchWindowController?
    private var sessionManager: SessionManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sessionManager = SessionManager()
        notchWindowController = NotchWindowController(sessionManager: sessionManager)
        notchWindowController?.showWindow(nil)

        installBridgeIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Bridge installation

    private func installBridgeIfNeeded() {
        guard let bridgeSource = bridgeBinaryPath() else {
            print("[ClawIsland] ClawBridge binary not found — hook integration disabled")
            return
        }
        do {
            try HookInstaller.install(bridgeSourcePath: bridgeSource)
            print("[ClawIsland] Bridge installed at \(HookInstaller.bridgeInstallPath)")
        } catch {
            print("[ClawIsland] Failed to install bridge: \(error)")
        }
    }

    /// Locate the ClawBridge binary inside the app bundle.
    /// XcodeGen embeds it at Contents/Resources/ClawBridge.
    private func bridgeBinaryPath() -> String? {
        if let path = Bundle.main.path(forResource: "ClawBridge", ofType: nil),
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fallback: MacOS/ sibling (when manually placing the binary)
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            let candidate = (execDir as NSString).appendingPathComponent("ClawBridge")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
