import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindowController: NotchWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var sessionManager: SessionManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sessionManager = SessionManager()
        sessionManager.soundManager = SoundManager()
        notchWindowController = NotchWindowController(sessionManager: sessionManager)

        settingsWindowController = SettingsWindowController()
        notchWindowController?.onOpenSettings = { [weak self] in
            self?.settingsWindowController?.toggleSettings()
        }

        notchWindowController?.showWindow(nil)
        installBridgeIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Bridge installation

    private func installBridgeIfNeeded() {
        // Install Claude bridge
        if let bridgeSource = bridgeBinaryPath(name: "ClawBridge") {
            do {
                try HookInstaller.install(bridgeSourcePath: bridgeSource)
                print("[ClawIsland] Claude bridge installed at \(HookInstaller.bridgeInstallPath)")
            } catch {
                print("[ClawIsland] Failed to install Claude bridge: \(error)")
            }
        } else {
            print("[ClawIsland] ClawBridge binary not found — Claude hook integration disabled")
        }

        // Install Codex bridge
        if let codexSource = bridgeBinaryPath(name: "CodexBridge") {
            do {
                try HookInstaller.installCodex(bridgeSourcePath: codexSource)
                print("[ClawIsland] Codex bridge installed at \(HookInstaller.codexBridgeInstallPath)")
            } catch {
                print("[ClawIsland] Failed to install Codex bridge: \(error)")
            }
        } else {
            print("[ClawIsland] CodexBridge binary not found — Codex hook integration disabled")
        }
    }

    /// Locate a bridge binary inside the app bundle.
    /// XcodeGen embeds them at Contents/Resources/.
    private func bridgeBinaryPath(name: String) -> String? {
        if let path = Bundle.main.path(forResource: name, ofType: nil),
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            let candidate = (execDir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
