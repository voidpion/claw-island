import Foundation
import UserNotifications

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []

    /// Controller sets this to be notified when a session needs the panel auto-expanded
    var onAutoExpand: (() -> Void)?

    private let socketServer = SocketServer()

    func start() {
        requestNotificationPermission()
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
            if e.notificationType == "permission_prompt" {
                return await handleNotificationPermissionPrompt(e)
            }
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
        let s = findOrNearest(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status = .waitingApproval(e)
        s.lastActivity = Date()
        onAutoExpand?()
        return await withCheckedContinuation { continuation in
            s.pendingApprovalContinuation = continuation
        }
    }

    private func handleNotificationPermissionPrompt(_ e: NotificationEvent) async -> HookResponse {
        let s = findOrNearest(id: e.sessionId, transcriptPath: e.transcriptPath)
        let fakeEvent = PermissionRequestEvent(
            sessionId: e.sessionId,
            transcriptPath: e.transcriptPath,
            toolName: "Permission",
            toolInput: .string(e.message)
        )
        s.status = .waitingApproval(fakeEvent)
        s.lastActivity = Date()
        onAutoExpand?()
        return await withCheckedContinuation { continuation in
            s.pendingApprovalContinuation = continuation
        }
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
        s.status = .notifying(message: msg)
        s.lastActivity = Date()
        onAutoExpand?()
        sendSystemNotification(title: e.title ?? s.title, body: msg, id: e.sessionId + "-notif")
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
        sendSystemNotification(
            title: "Task Completed",
            body: "\(s.title) · \(s.elapsedTime)",
            id: s.id + "-stop"
        )
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

    func approve(session: Session) {
        NSLog("[ClawIsland] approve called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .allow, reason: nil)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    func deny(session: Session, reason: String? = nil) {
        NSLog("[ClawIsland] deny called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .deny, reason: reason)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    /// Silently allow — dismisses the approval UI without surfacing a decision to the model.
    func ignore(session: Session) {
        NSLog("[ClawIsland] ignore called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .allow, reason: nil)
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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendSystemNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
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
