import Foundation

/// Installs the ClawBridge binary to a stable path and registers it
/// in ~/.claude/settings.json for all relevant hook events.
struct HookInstaller {

    /// Stable install location for the Claude bridge binary
    static let bridgeInstallPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".claw-island/bin/claw-bridge")

    /// Stable install location for the Codex bridge binary
    static let codexBridgeInstallPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".claw-island/bin/claw-codex-bridge")

    // Claude Code hook events.
    // PermissionRequest needs a 24h timeout since it blocks until user responds.
    // Others are fire-and-forget.
    private static let claudeHookEvents: [(name: String, timeout: Int?)] = [
        ("PermissionRequest",  86400),   // blocks — long timeout
        ("PreToolUse",         nil),
        ("PostToolUse",        nil),
        ("PostToolUseFailure", nil),
        ("Notification",       nil),
        ("SessionStart",       nil),
        ("SessionEnd",         nil),
        ("Stop",               nil),
        ("StopFailure",        nil),
        ("SubagentStart",      nil),
        ("SubagentStop",       nil),
        ("UserPromptSubmit",   nil),
        ("PreCompact",         nil),
        ("PostCompact",        nil),
    ]

    // Codex CLI hook events (subset, all fire-and-forget).
    private static let codexHookEvents: [String] = [
        "SessionStart",
        "PreToolUse",
        "PostToolUse",
        "UserPromptSubmit",
        "Stop",
    ]

    // MARK: - Public API

    /// Copy Claude bridge binary to stable path and update ~/.claude/settings.json.
    static func install(bridgeSourcePath sourcePath: String) throws {
        try installBinary(from: sourcePath, to: bridgeInstallPath)
        try registerClaudeHooks()
    }

    /// Copy Codex bridge binary and register hooks. Picks `hooks.json` or
    /// `config.toml` based on what the user already uses, and cleans up the
    /// other file so Codex doesn't warn about duplicate hook sources.
    static func installCodex(bridgeSourcePath sourcePath: String) throws {
        try installBinary(from: sourcePath, to: codexBridgeInstallPath)

        switch codexHookTarget() {
        case .configToml:
            try writeCodexHooksToConfigToml()
            try? deregisterCodexHooks()
            cleanupCodexHooksJsonIfEmpty()
        case .hooksJson:
            try registerCodexHooks()
            try? removeManagedBlockFromConfigToml()
        }

        try enableCodexHooksFeature()
    }

    static func uninstall() throws {
        try deregisterClaudeHooks()
    }

    static func uninstallCodex() throws {
        try? deregisterCodexHooks()
        cleanupCodexHooksJsonIfEmpty()
        try? removeManagedBlockFromConfigToml()
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: bridgeInstallPath)
    }

    static var isCodexInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: codexBridgeInstallPath)
    }

    /// Check whether all required Claude hooks are registered.
    static func validateHooks() -> Bool {
        let settingsURL = claudeSettingsURL()
        let settings = readSettings(at: settingsURL)
        let hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, _) in claudeHookEvents {
            guard let entries = hooks[event] as? [[String: Any]],
                  entries.contains(where: isClaIslandEntry) else {
                return false
            }
        }
        return true
    }

    /// Check whether Codex hooks are registered (in either hooks.json or
    /// config.toml) and the feature flag is enabled.
    static func validateCodexHooks() -> Bool {
        let registered = codexHooksJsonHasAllEntries() || configTomlHasManagedBlock()
        return registered && isCodexHooksEnabled()
    }

    private static func codexHooksJsonHasAllEntries() -> Bool {
        let hooksURL = codexHooksURL()
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return false }
        let hooks = readJSON(at: hooksURL)
        let hookEntries = hooks["hooks"] as? [String: Any] ?? [:]
        for event in codexHookEvents {
            guard let entries = hookEntries[event] as? [[String: Any]],
                  entries.contains(where: isCodexIslandEntry) else {
                return false
            }
        }
        return true
    }

    // MARK: - Binary installation

    private static func installBinary(from sourcePath: String, to destPath: String) throws {
        let fm = FileManager.default
        let dir = (destPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Only overwrite if source is newer (avoids re-copying on every launch)
        let srcAttrs = try fm.attributesOfItem(atPath: sourcePath)
        let srcMod = srcAttrs[.modificationDate] as? Date ?? .distantPast

        if fm.fileExists(atPath: destPath) {
            let dstAttrs = (try? fm.attributesOfItem(atPath: destPath)) ?? [:]
            let dstMod = dstAttrs[.modificationDate] as? Date ?? .distantPast
            if srcMod <= dstMod { return }   // already up to date
            try fm.removeItem(atPath: destPath)
        }

        try fm.copyItem(atPath: sourcePath, toPath: destPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
    }

    // MARK: - Claude hooks registration

    private static func registerClaudeHooks() throws {
        let settingsURL = claudeSettingsURL()

        var settings = readSettings(at: settingsURL)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, timeout) in claudeHookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { isClaIslandEntry($0) }

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

    private static func deregisterClaudeHooks() throws {
        let settingsURL = claudeSettingsURL()
        var settings = readSettings(at: settingsURL)
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for (event, _) in claudeHookEvents {
            if var entries = hooks[event] as? [[String: Any]] {
                entries.removeAll { isClaIslandEntry($0) }
                hooks[event] = entries.isEmpty ? nil : entries
            }
        }
        settings["hooks"] = hooks
        try writeSettings(settings, to: settingsURL)
    }

    // MARK: - Codex hooks registration

    private static func registerCodexHooks() throws {
        let hooksURL = codexHooksURL()
        var hooks = readJSON(at: hooksURL)
        var hookEntries = hooks["hooks"] as? [String: Any] ?? [:]

        for event in codexHookEvents {
            var entries = hookEntries[event] as? [[String: Any]] ?? []
            entries.removeAll { isCodexIslandEntry($0) }

            let hookEntry: [String: Any] = [
                "type": "command",
                "command": codexBridgeInstallPath,
            ]

            let matcher: [String: Any] = [
                "matcher": ".*",
                "hooks": [hookEntry],
            ]
            entries.append(matcher)
            hookEntries[event] = entries
        }

        hooks["hooks"] = hookEntries
        try writeJSON(hooks, to: hooksURL)
    }

    private static func deregisterCodexHooks() throws {
        let hooksURL = codexHooksURL()
        var hooks = readJSON(at: hooksURL)
        guard var hookEntries = hooks["hooks"] as? [String: Any] else { return }

        for event in codexHookEvents {
            if var entries = hookEntries[event] as? [[String: Any]] {
                entries.removeAll { isCodexIslandEntry($0) }
                hookEntries[event] = entries.isEmpty ? nil : entries
            }
        }
        hooks["hooks"] = hookEntries
        try writeJSON(hooks, to: hooksURL)
    }

    // MARK: - Codex hook target selection & config.toml managed block

    private enum CodexHookTarget { case hooksJson, configToml }

    private static let codexConfigSentinelStart = "# >>> claw-island codex hooks (managed) >>>"
    private static let codexConfigSentinelEnd = "# <<< claw-island codex hooks (managed) <<<"

    /// Decide where Codex hooks should live. If the user (or new-version Codex)
    /// already declares `[hooks]` / `[[hooks.X]]` in config.toml outside our
    /// managed block, we follow them there. Otherwise default to hooks.json.
    private static func codexHookTarget() -> CodexHookTarget {
        configTomlHasNonManagedHooks() ? .configToml : .hooksJson
    }

    private static func configTomlHasNonManagedHooks() -> Bool {
        guard let content = try? String(contentsOf: codexConfigURL(), encoding: .utf8) else {
            return false
        }
        let stripped = removeManagedBlock(content)
        let pattern = #"(?m)^[ \t]*(\[hooks\]|\[\[hooks\.)"#
        return stripped.range(of: pattern, options: .regularExpression) != nil
    }

    private static func configTomlHasManagedBlock() -> Bool {
        guard let content = try? String(contentsOf: codexConfigURL(), encoding: .utf8) else {
            return false
        }
        return content.contains(codexConfigSentinelStart) && content.contains(codexConfigSentinelEnd)
    }

    private static func renderCodexHooksTomlBlock() -> String {
        var lines: [String] = [codexConfigSentinelStart]
        for event in codexHookEvents {
            lines.append("[[hooks.\(event)]]")
            lines.append("command = \"\(codexBridgeInstallPath)\"")
            lines.append("")
        }
        lines.append(codexConfigSentinelEnd)
        return lines.joined(separator: "\n")
    }

    private static func writeCodexHooksToConfigToml() throws {
        let url = codexConfigURL()
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        content = removeManagedBlock(content)
        if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
        if !content.isEmpty { content += "\n" }
        content += renderCodexHooksTomlBlock() + "\n"

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removeManagedBlockFromConfigToml() throws {
        let url = codexConfigURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let cleaned = removeManagedBlock(content)
        if cleaned != content {
            try cleaned.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func removeManagedBlock(_ content: String) -> String {
        guard let startRange = content.range(of: codexConfigSentinelStart),
              let endRange = content.range(
                of: codexConfigSentinelEnd,
                range: startRange.upperBound..<content.endIndex
              )
        else { return content }

        var lower = startRange.lowerBound
        while lower > content.startIndex {
            let prev = content.index(before: lower)
            if content[prev] == "\n" { lower = prev } else { break }
        }
        var upper = endRange.upperBound
        if upper < content.endIndex, content[upper] == "\n" {
            upper = content.index(after: upper)
        }
        return String(content[content.startIndex..<lower]) + String(content[upper..<content.endIndex])
    }

    /// If hooks.json exists but no longer contains any meaningful entries,
    /// delete it so Codex doesn't load an empty file alongside config.toml.
    private static func cleanupCodexHooksJsonIfEmpty() {
        let url = codexHooksURL()
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let json = readJSON(at: url)
        let hookEntries = json["hooks"] as? [String: Any] ?? [:]
        let hasAnyEntries = hookEntries.values.contains { value in
            if let arr = value as? [[String: Any]] { return !arr.isEmpty }
            return false
        }
        let otherKeys = json.keys.filter { $0 != "hooks" }
        if !hasAnyEntries && otherKeys.isEmpty {
            try? fm.removeItem(at: url)
        }
    }

    /// Enable codex_hooks feature flag in ~/.codex/config.toml.
    private static func enableCodexHooksFeature() throws {
        let configURL = codexConfigURL()
        let fm = FileManager.default

        var content: String
        if let data = try? Data(contentsOf: configURL),
           let existing = String(data: data, encoding: .utf8) {
            content = existing
        } else {
            content = ""
        }

        // Ensure [features] section exists with codex_hooks = true
        if content.contains("codex_hooks") {
            // Replace existing value
            if let range = content.range(of: #"codex_hooks\s*=\s*\S+"#, options: .regularExpression) {
                content.replaceSubrange(range, with: "codex_hooks = true")
            }
        } else if content.contains("[features]") {
            // Add to existing [features] section
            if let range = content.range(of: "[features]") {
                content.insert(contentsOf: "\ncodex_hooks = true", at: range.upperBound)
            }
        } else {
            // Add new [features] section
            if !content.hasSuffix("\n") { content += "\n" }
            content += "\n[features]\ncodex_hooks = true\n"
        }

        let dir = configURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func isCodexHooksEnabled() -> Bool {
        let configURL = codexConfigURL()
        guard let data = try? Data(contentsOf: configURL),
              let content = String(data: data, encoding: .utf8) else { return false }
        // Simple check: look for codex_hooks = true
        return content.contains("codex_hooks = true") || content.contains("codex_hooks=true")
    }

    // MARK: - Helpers

    private static func isClaIslandEntry(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { hook in
            (hook["command"] as? String)?.contains("claw-bridge") == true
        }
    }

    private static func isCodexIslandEntry(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { hook in
            (hook["command"] as? String)?.contains("claw-codex-bridge") == true
        }
    }

    /// Detect third-party bridges that compete for PermissionRequest handling.
    private static func isCompetingPermissionBridge(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { hook in
            guard let cmd = hook["command"] as? String else { return false }
            if cmd.contains("claw-bridge") { return false }
            return true
        }
    }

    private static func claudeSettingsURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    private static func codexHooksURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/hooks.json")
    }

    private static func codexConfigURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/config.toml")
    }

    private static func readSettings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func readJSON(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }
}
