import Foundation

/// Installs the ClawBridge binary to a stable path and registers it
/// in ~/.claude/settings.json for all relevant hook events.
struct HookInstaller {

    /// Stable install location for the bridge binary
    static let bridgeInstallPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".claw-island/bin/claw-bridge")

    // Hook events that should be registered.
    // PermissionRequest needs a 24h timeout since it blocks until user responds.
    // Others are fire-and-forget.
    private static let hookEvents: [(name: String, timeout: Int?)] = [
        ("PermissionRequest",  86400),   // blocks — long timeout
        ("PreToolUse",         nil),
        ("PostToolUse",        nil),
        ("Notification",       nil),
        ("SessionStart",       nil),
        ("SessionEnd",         nil),
        ("Stop",               nil),
        ("SubagentStart",      nil),
        ("SubagentStop",       nil),
        ("UserPromptSubmit",   nil),
        ("PreCompact",         nil),
    ]

    // MARK: - Public API

    /// Copy bridge binary to stable path and update ~/.claude/settings.json.
    /// `sourcePath` is the path of the built ClawBridge binary (from the app bundle).
    static func install(bridgeSourcePath sourcePath: String) throws {
        try installBinary(from: sourcePath)
        try registerHooks()
    }

    static func uninstall() throws {
        try deregisterHooks()
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: bridgeInstallPath)
    }

    // MARK: - Binary installation

    private static func installBinary(from sourcePath: String) throws {
        let fm = FileManager.default
        let dir = (bridgeInstallPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Only overwrite if source is newer (avoids re-copying on every launch)
        let srcAttrs = try fm.attributesOfItem(atPath: sourcePath)
        let srcMod = srcAttrs[.modificationDate] as? Date ?? .distantPast

        if fm.fileExists(atPath: bridgeInstallPath) {
            let dstAttrs = (try? fm.attributesOfItem(atPath: bridgeInstallPath)) ?? [:]
            let dstMod = dstAttrs[.modificationDate] as? Date ?? .distantPast
            if srcMod <= dstMod { return }   // already up to date
            try fm.removeItem(atPath: bridgeInstallPath)
        }

        try fm.copyItem(atPath: sourcePath, toPath: bridgeInstallPath)
        // Ensure executable bit
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgeInstallPath)
    }

    // MARK: - Hooks registration

    private static func registerHooks() throws {
        let settingsURL = claudeSettingsURL()

        var settings = readSettings(at: settingsURL)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, timeout) in hookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            // Remove any stale claw-island entries
            entries.removeAll { isClaIslandEntry($0) }

            // For PermissionRequest, remove competing bridges that would
            // auto-allow and bypass our approval UI (e.g. vibe-island-bridge
            // when Vibe Island is not running).
            if event == "PermissionRequest" {
                entries.removeAll { isCompetingPermissionBridge($0) }
            }

            var hookEntry: [String: Any] = [
                "type": "command",
                "command": bridgeInstallPath,
            ]
            if let t = timeout { hookEntry["timeout"] = t }

            let matcher: [String: Any] = [
                "matcher": "*",
                "hooks": [hookEntry],
            ]
            entries.append(matcher)
            hooks[event] = entries
        }

        settings["hooks"] = hooks
        try writeSettings(settings, to: settingsURL)
    }

    private static func deregisterHooks() throws {
        let settingsURL = claudeSettingsURL()
        var settings = readSettings(at: settingsURL)
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for (event, _) in hookEvents {
            if var entries = hooks[event] as? [[String: Any]] {
                entries.removeAll { isClaIslandEntry($0) }
                hooks[event] = entries.isEmpty ? nil : entries
            }
        }
        settings["hooks"] = hooks
        try writeSettings(settings, to: settingsURL)
    }

    // MARK: - Helpers

    private static func isClaIslandEntry(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { hook in
            (hook["command"] as? String)?.contains("claw-bridge") == true
        }
    }

    /// Detect third-party bridges that compete for PermissionRequest handling.
    /// These must be removed because they auto-allow when their host app isn't
    /// running, which bypasses our approval UI entirely.
    private static func isCompetingPermissionBridge(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { hook in
            guard let cmd = hook["command"] as? String else { return false }
            // Skip our own entry
            if cmd.contains("claw-bridge") { return false }
            // Any other command hook for PermissionRequest is a competitor
            return true
        }
    }

    private static func claudeSettingsURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    private static func readSettings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }
}
