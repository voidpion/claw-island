import AppKit
import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []

    /// Controller sets this to be notified when a session needs the panel auto-expanded
    var onAutoExpand: (() -> Void)?

    private let socketServer = SocketServer()

    func start() {
        try? socketServer.start { [weak self] event in
            guard let self else { return nil }
            return await self.handle(event: event)
        }
        recoverExistingSessions()
    }

    // MARK: - Event routing

    private func handle(event: HookEvent) async -> HookResponse? {
        switch event {
        case .sessionStart(let e):      handleSessionStart(e)
        case .permissionRequest(let e): return await handlePermissionRequest(e)
        case .preToolUse(let e):        handlePreToolUse(e)
        case .postToolUse(let e):       handlePostToolUse(e)
        case .notification(let e):
            handleNotification(e)
        case .stop(let e):              handleStop(e)
        case .sessionEnd(let e):        handleSessionEnd(e)
        case .userPromptSubmit(let e):  handleUserPromptSubmit(e)
        case .preCompact(let e):        handlePreCompact(e)
        case .subagentStart(let e):     handleSubagentStart(e)
        case .subagentStop(let e):      handleSubagentStop(e)
        case .unknown:                  break
        }
        return nil
    }

    // MARK: - Handlers

    private func handleSessionStart(_ e: SessionStartEvent) {
        debugLog("handleSessionStart id=\(e.sessionId) sessions.count=\(sessions.count)")
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.lastActivity = Date()
        if let model = e.model { s.model = model }
        if let cwd = e.cwd { s.cwd = cwd }
        if let tty = e.tty { s.tty = tty }
        debugLog("handleSessionStart id=\(e.sessionId.prefix(8)) tty=\(e.tty ?? "nil") cwd=\(e.cwd ?? "nil")")
        // compact / resume: session continues — preserve title, start time, and status.
        // startup / clear / unknown: fresh session, fully reset.
        let isContinuation = e.source == "compact" || e.source == "resume"
        if isContinuation {
            s.subagentCount = 0
            // Keep current status (e.g. .compacting → stays until next event updates it)
            // rather than flashing back to idle mid-conversation.
        } else {
            s.status = .idle
            s.currentTool = nil
            s.startTime = Date()
            s.customTitle = nil
            s.subagentCount = 0
        }
        // Read initial title & model from transcript JSONL
        if let path = e.transcriptPath {
            let info = Self.parseTranscript(path: path)
            if let t = info.title, s.customTitle == nil { s.customTitle = t }
            if let m = info.model, s.model == nil { s.model = m }
            // Derive cwd from transcript path as fallback (event cwd preferred)
            if s.cwd == nil {
                let dirName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
                if dirName.hasPrefix("-") {
                    s.cwd = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")
                }
            }
        }
    }

    private func handlePermissionRequest(_ e: PermissionRequestEvent) async -> HookResponse {
        debugLog("handlePermissionRequest: session \(e.sessionId.prefix(8)), tool=\(e.toolName)")
        let s = findOrNearest(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status = .waitingApproval(e)
        s.lastActivity = Date()
        onAutoExpand?()
        debugLog("handlePermissionRequest: waiting for user action on session \(s.id.prefix(8))")
        let response = await withCheckedContinuation { continuation in
            s.pendingApprovalContinuation = continuation
            debugLog("handlePermissionRequest: continuation stored for session \(s.id.prefix(8)), continuation present: \(s.pendingApprovalContinuation != nil)")
        }
        debugLog("handlePermissionRequest: got response decision=\(response.decision) for session \(s.id.prefix(8))")
        return response
    }

    private func handlePreToolUse(_ e: PreToolUseEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        let desc = Self.toolDescription(name: e.toolName, input: e.toolInput, cwd: s.cwd)
        s.status      = .running(toolName: desc)
        s.currentTool = e.toolName
        s.lastActivity = Date()
    }

    /// Build a single-line tool description: "ToolName: key_param"
    /// Strips cwd prefix from file paths for cleaner display.
    private static func toolDescription(name: String, input: JSONValue, cwd: String?) -> String {
        let raw: String? = {
            switch name {
            case "Bash":   return input["command"]?.description
            case "Read":   return input["file_path"]?.description
            case "Write":  return input["file_path"]?.description
            case "Edit":   return input["file_path"]?.description
            case "Grep":   return input["pattern"]?.description
            case "Glob":   return input["pattern"]?.description
            case "Agent":  return input["description"]?.description
            case "WebFetch", "WebSearch": return input["query"]?.description ?? input["url"]?.description
            default:       return nil
            }
        }()
        guard let raw else { return name }
        var display = raw
        if let cwd, display.hasPrefix(cwd + "/") {
            display = String(display.dropFirst(cwd.count + 1))
        }
        return "\(name): \(display)"
    }

    private func handlePostToolUse(_ e: PostToolUseEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        // Stay in running state — next pre_tool_use will update the tool name,
        // or stop will transition to completed. No idle flash mid-conversation.
        s.lastActivity = Date()
    }

    private func handleNotification(_ e: NotificationEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        let msg = e.message.trimmingCharacters(in: .whitespacesAndNewlines)
        // 不覆盖正在等待审批的 session — approval UI 优先级最高
        if case .waitingApproval = s.status { } else {
            s.status = .notifying(message: msg)
        }
        s.lastActivity = Date()
        onAutoExpand?()
    }

    private func handleUserPromptSubmit(_ e: UserPromptSubmitEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        let trimmed = e.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Only set once — first prompt establishes the session title; later prompts don't override.
            if s.customTitle == nil {
                s.customTitle = trimmed
            }
            s.lastUserPrompt = trimmed
        }
        // Show as running("thinking") — Claude has received the message and is about to work.
        // pre_tool_use will replace this with the actual tool name shortly.
        s.status = .running(toolName: "thinking")
        s.currentTool = nil
        s.lastActivity = Date()
    }

    private func handlePreCompact(_ e: PreCompactEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status = .compacting
        s.lastActivity = Date()
    }

    private func handleStop(_ e: StopEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status      = .completed
        s.currentTool = nil
        s.lastActivity = Date()
        onAutoExpand?()
        // Do NOT remove here — Stop fires after every response, not just at session end.
        // SessionEnd handles removal when the user actually exits claude.
    }

    private func handleSessionEnd(_ e: SessionEndEvent) {
        // User exited claude — remove after a brief delay so "Done" is readable.
        Task {
            try? await Task.sleep(for: .seconds(5))
            sessions.removeAll { $0.id == e.sessionId }
        }
    }

    private func handleSubagentStart(_ e: SubagentStartEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.subagentCount += 1
        s.lastActivity = Date()
    }

    private func handleSubagentStop(_ e: SubagentStopEvent) {
        guard let s = sessions.first(where: { $0.id == e.sessionId }) else { return }
        s.subagentCount = max(0, s.subagentCount - 1)
        s.lastActivity = Date()
    }

    // MARK: - Approval (called from UI)

    func approve(session: Session, updatedPermissions: [JSONValue]? = nil) {
        NSLog("[ClawIsland] approve called — continuation present: %d, updatedPermissions: %d", session.pendingApprovalContinuation != nil ? 1 : 0, updatedPermissions != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .allow, reason: nil, updatedPermissions: updatedPermissions)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    func deny(session: Session, reason: String? = nil) {
        NSLog("[ClawIsland] deny called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .deny, reason: reason, updatedPermissions: nil)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    // MARK: - Startup recovery

    /// Scan ~/.claude/sessions/ for already-running Claude Code processes
    /// and create placeholder sessions so they appear in the notch UI immediately.
    private func recoverExistingSessions() {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) else { return }

        for fileURL in files {
            guard fileURL.pathExtension == "json",
                  let data = try? Data(contentsOf: fileURL),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = obj["pid"] as? Int,
                  let sessionId = obj["sessionId"] as? String,
                  let cwd = obj["cwd"] as? String
            else { continue }

            // Skip non-CLI sessions (e.g. Xcode sdk-ts integration)
            if (obj["entrypoint"] as? String) == "sdk-ts" { continue }

            // Check if process is still alive
            guard kill(pid_t(pid), 0) == 0 else { continue }

            // Skip if we already have this session (from hooks)
            if sessions.contains(where: { $0.id == sessionId }) { continue }

            // Derive transcriptPath from cwd: "/Users/zhangjin/..." → "-Users-zhangjin-..."
            let projectDir = "-" + cwd.dropFirst().replacingOccurrences(of: "/", with: "-")
            let transcriptPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects/\(projectDir)/\(sessionId).jsonl")
                .path

            let s = findOrCreate(id: sessionId, transcriptPath: transcriptPath)
            s.status = .idle
            s.lastActivity = Date()
            s.cwd = cwd
            s.pid = pid_t(pid)

            // 用 sysctl 获取该进程的 controlling terminal
            var kinfo = kinfo_proc()
            var kinfoSize = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid_t(pid)]
            if sysctl(&mib, 4, &kinfo, &kinfoSize, nil, 0) == 0 {
                let dev = kinfo.kp_eproc.e_tdev
                if dev != 0 && dev != -1, let ptr = devname(dev, S_IFCHR) {
                    s.tty = "/dev/" + String(cString: ptr)
                }
            }

            // Set startTime from startedAt (epoch ms)
            if let startedAt = obj["startedAt"] as? TimeInterval {
                s.startTime = Date(timeIntervalSince1970: startedAt / 1000)
            }

            // Extract title, model & last prompt from transcript
            let info = Self.parseTranscript(path: transcriptPath)
            if let t = info.title { s.customTitle = t }
            if let m = info.model { s.model = m }
            if let p = info.lastUserPrompt { s.lastUserPrompt = p }

            debugLog("recovered session \(sessionId.prefix(8)) cwd=\(cwd)")
        }
    }

    // MARK: - Helpers

    private func findOrCreate(id: String, transcriptPath: String?) -> Session {
        if let existing = sessions.first(where: { $0.id == id }) { return existing }
        let s = Session(id: id, transcriptPath: transcriptPath)
        sessions.append(s)
        debugLog("findOrCreate: created new session, total=\(sessions.count)")
        return s
    }

    /// Like findOrCreate, but for events that should NOT spawn a new row
    /// (e.g., permission requests from sub-agents). Falls back to the
    /// most-recently-active session if the exact ID isn't found.
    private func findOrNearest(id: String, transcriptPath: String?) -> Session {
        if let existing = sessions.first(where: { $0.id == id }) { return existing }
        // No exact match — attach to the most recently active session
        if let nearest = sessions.max(by: { $0.lastActivity < $1.lastActivity }) {
            debugLog("findOrNearest: no match for \(id), attaching to \(nearest.id)")
            return nearest
        }
        // No sessions at all — create one as last resort
        return findOrCreate(id: id, transcriptPath: transcriptPath)
    }

    private func debugLog(_ msg: String) {
        let line = "\(Date()) [SM] \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/claw-island.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Window focus

    /// 点击 session 行时，激活对应的终端/编辑器窗口。
    /// 策略：进程树向上找到终端 app → AX API 枚举窗口 → 按 cwd 目录名匹配标题 → raise 指定窗口。
    func focusWindow(for session: Session) {
        let claudePid: pid_t
        if let stored = session.pid {
            claudePid = stored
        } else if let found = lookupPID(sessionId: session.id) {
            claudePid = found
        } else {
            return
        }
        guard let app = findAncestorApp(of: claudePid) else { return }

        if AXIsProcessTrusted() {
            if let tty = session.tty {
                raiseWindowByTTY(appPid: app.processIdentifier, session: session, tty: tty)
            } else {
                raiseWindow(appPid: app.processIdentifier, session: session)
            }
        } else {
            let key = "AXTrustedCheckOptionPrompt" as CFString
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    /// 向 tty slave 写入 OSC 标题转义序列，等终端刷新标题后用 AX API 找到对应窗口并 raise。
    /// 原理：写入 slave → 终端模拟器从 master 读取 → 更新窗口/tab 标题 → AX 可见。
    private func raiseWindowByTTY(appPid: pid_t, session: Session, tty: String) {
        let marker = "claw-\(session.id.prefix(8))"
        let osc     = "\u{1B}]0;\(marker)\u{07}"

        let fd = Darwin.open(tty, O_WRONLY | O_NOCTTY)
        guard fd >= 0 else { raiseWindow(appPid: appPid, session: session); return }
        let written = osc.withCString { Darwin.write(fd, $0, strlen($0)) }
        Darwin.close(fd)
        guard written > 0 else { raiseWindow(appPid: appPid, session: session); return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 先 activate — 触发 macOS 将跨 Space 的窗口暴露给 AX
            NSRunningApplication(processIdentifier: appPid)?.activate(options: .activateIgnoringOtherApps)
            try? await Task.sleep(for: .milliseconds(150))

            let axApp = AXUIElementCreateApplication(appPid)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return }

            // 优先 OSC marker 匹配，其次 cwd 目录名匹配
            let cwdName = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            var oscTarget: AXUIElement?
            var cwdTarget: AXUIElement?

            for window in windows {
                var titleRef: AnyObject?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                      let title = titleRef as? String else { continue }
                debugLog("raiseWindowByTTY: window title='\(title)'")
                if title.contains(marker) { oscTarget = window; break }
                if !cwdName.isEmpty && title.contains(cwdName) { cwdTarget = window }
            }

            let target = oscTarget ?? cwdTarget
            if let target {
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            }

            // 恢复窗口标题为 cwd 最后一段
            guard !cwdName.isEmpty else { return }
            let restoreOsc = "\u{1B}]0;\(cwdName)\u{07}"
            let rfd = Darwin.open(tty, O_WRONLY | O_NOCTTY)
            if rfd >= 0 {
                restoreOsc.withCString { _ = Darwin.write(rfd, $0, strlen($0)) }
                Darwin.close(rfd)
            }
        }
    }

    /// 按 cwd 目录名匹配窗口标题（tty 不可用时的 fallback）。
    private func raiseWindow(appPid: pid_t, session: Session) {
        let axApp = AXUIElementCreateApplication(appPid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            NSRunningApplication(processIdentifier: appPid)?.activate(options: .activateIgnoringOtherApps)
            return
        }

        let dirName = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        var target: AXUIElement = windows[0]
        if !dirName.isEmpty {
            for window in windows {
                var titleRef: AnyObject?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, title.contains(dirName) {
                    target = window
                    break
                }
            }
        }

        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: appPid)?.activate(options: .activateIgnoringOtherApps)
    }

    /// 从 ~/.claude/sessions/<id>.json 读取 PID。
    private func lookupPID(sessionId: String) -> pid_t? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions/\(sessionId).json")
        guard let data = try? Data(contentsOf: url),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid  = obj["pid"] as? Int else { return nil }
        return pid_t(pid)
    }

    /// sysctl로 指定 PID 의 부모 PID 를 반환。
    private func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 1 ? ppid : nil
    }

    /// 向上遍历进程树，返回第一个有 bundle ID 的 macOS app（即终端/编辑器）。
    private func findAncestorApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<10 {
            guard let ppid = parentPID(of: current) else { break }
            if let app = NSRunningApplication(processIdentifier: ppid),
               app.bundleIdentifier != nil {
                return app
            }
            current = ppid
        }
        return nil
    }

    // MARK: - Transcript parsing

    struct TranscriptInfo {
        var title: String?           // first real user message (≤40 chars)
        var model: String?           // last non-synthetic model name
        var lastUserPrompt: String?  // last real user message (≤60 chars)
    }

    /// Scan transcript JSONL: forward for first user message, backward for last model + last user message.
    private static func parseTranscript(path: String) -> TranscriptInfo {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return TranscriptInfo()
        }

        let allLines = data.split(separator: 0x0A, omittingEmptySubsequences: true)

        var firstUserContent: String?
        var lastModel: String?
        var lastUserPrompt: String?

        // Forward pass: find first user message
        for line in allLines {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            if obj["type"] as? String == "user",
               let text = Self.extractUserText(obj) {
                firstUserContent = text
                break
            }
        }

        // Reverse pass: find last model + last user message
        for line in allLines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            let type = obj["type"] as? String

            if type == "assistant", lastModel == nil,
               let message = obj["message"] as? [String: Any],
               let model = message["model"] as? String, model != "<synthetic>" {
                lastModel = Self.shortModelName(model)
            }

            if type == "user", lastUserPrompt == nil,
               let text = Self.extractUserText(obj) {
                lastUserPrompt = text
            }

            if lastModel != nil && lastUserPrompt != nil { break }
        }

        return TranscriptInfo(title: firstUserContent, model: lastModel, lastUserPrompt: lastUserPrompt)
    }

    /// Extract real user text from a user-type JSONL entry, skipping meta/system messages.
    private static func extractUserText(_ obj: [String: Any]) -> String? {
        guard let message = obj["message"] as? [String: Any] else { return nil }
        if let content = message["content"] as? String, !content.hasPrefix("<") {
            return content
        }
        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                guard item["type"] as? String == "text",
                      let text = item["text"] as? String,
                      !text.hasPrefix("<") else { continue }
                return text
            }
        }
        return nil
    }

    /// Shorten model IDs for display: "claude-sonnet-4-6" → "sonnet-4.6", "glm-5.1" → "glm-5.1"
    private static func shortModelName(_ raw: String) -> String {
        if raw.hasPrefix("claude-") {
            let rest = String(raw.dropFirst(7)) // drop "claude-"
            let parts = rest.components(separatedBy: "-")
            if parts.count >= 2 {
                let family = parts[0] // sonnet, opus, haiku
                let version = parts[1...].joined(separator: ".")
                return "\(family)-\(version)"
            }
        }
        return raw
    }
}
