import Foundation

// MARK: - Incoming events from Claude Code hooks
// Claude Code passes all events via stdin as JSON.
// The JSON always contains `hook_event_name` (the event type discriminator)
// plus `session_id` and `transcript_path` in the base payload.

enum HookEvent: Codable, Sendable {
    case permissionRequest(PermissionRequestEvent)
    case preToolUse(PreToolUseEvent)
    case postToolUse(PostToolUseEvent)
    case notification(NotificationEvent)
    case sessionStart(SessionStartEvent)
    case sessionEnd(SessionEndEvent)
    case stop(StopEvent)
    case subagentStart(SubagentStartEvent)
    case subagentStop(SubagentStopEvent)
    case userPromptSubmit(UserPromptSubmitEvent)
    case preCompact(PreCompactEvent)
    case postCompact(PostCompactEvent)
    case postToolUseFailure(PostToolUseFailureEvent)
    case stopFailure(StopFailureEvent)
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .hookEventName)
        switch name {
        case "PermissionRequest":
            self = .permissionRequest(try PermissionRequestEvent(from: decoder))
        case "PreToolUse":
            self = .preToolUse(try PreToolUseEvent(from: decoder))
        case "PostToolUse":
            self = .postToolUse(try PostToolUseEvent(from: decoder))
        case "Notification":
            self = .notification(try NotificationEvent(from: decoder))
        case "SessionStart":
            self = .sessionStart(try SessionStartEvent(from: decoder))
        case "SessionEnd":
            self = .sessionEnd(try SessionEndEvent(from: decoder))
        case "Stop":
            self = .stop(try StopEvent(from: decoder))
        case "SubagentStart":
            self = .subagentStart(try SubagentStartEvent(from: decoder))
        case "SubagentStop":
            self = .subagentStop(try SubagentStopEvent(from: decoder))
        case "UserPromptSubmit":
            self = .userPromptSubmit(try UserPromptSubmitEvent(from: decoder))
        case "PreCompact":
            self = .preCompact(try PreCompactEvent(from: decoder))
        case "PostCompact":
            self = .postCompact(try PostCompactEvent(from: decoder))
        case "PostToolUseFailure":
            self = .postToolUseFailure(try PostToolUseFailureEvent(from: decoder))
        case "StopFailure":
            self = .stopFailure(try StopFailureEvent(from: decoder))
        default:
            self = .unknown(name)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .permissionRequest(let e): try e.encode(to: encoder)
        case .preToolUse(let e): try e.encode(to: encoder)
        case .postToolUse(let e): try e.encode(to: encoder)
        case .notification(let e): try e.encode(to: encoder)
        case .sessionStart(let e): try e.encode(to: encoder)
        case .sessionEnd(let e): try e.encode(to: encoder)
        case .stop(let e): try e.encode(to: encoder)
        case .subagentStart(let e): try e.encode(to: encoder)
        case .subagentStop(let e): try e.encode(to: encoder)
        case .userPromptSubmit(let e): try e.encode(to: encoder)
        case .preCompact(let e): try e.encode(to: encoder)
        case .postCompact(let e): try e.encode(to: encoder)
        case .postToolUseFailure(let e): try e.encode(to: encoder)
        case .stopFailure(let e): try e.encode(to: encoder)
        case .unknown: break
        }
    }

    var sessionId: String {
        switch self {
        case .permissionRequest(let e): e.sessionId
        case .preToolUse(let e): e.sessionId
        case .postToolUse(let e): e.sessionId
        case .notification(let e): e.sessionId
        case .sessionStart(let e): e.sessionId
        case .sessionEnd(let e): e.sessionId
        case .stop(let e): e.sessionId
        case .subagentStart(let e): e.sessionId
        case .subagentStop(let e): e.sessionId
        case .userPromptSubmit(let e): e.sessionId
        case .preCompact(let e): e.sessionId
        case .postCompact(let e): e.sessionId
        case .postToolUseFailure(let e): e.sessionId
        case .stopFailure(let e): e.sessionId
        case .unknown: ""
        }
    }

    var transcriptPath: String? {
        switch self {
        case .permissionRequest(let e): e.transcriptPath
        case .preToolUse(let e): e.transcriptPath
        case .postToolUse(let e): e.transcriptPath
        case .notification(let e): e.transcriptPath
        case .sessionStart(let e): e.transcriptPath
        case .sessionEnd(let e): e.transcriptPath
        case .stop(let e): e.transcriptPath
        case .subagentStart(let e): e.transcriptPath
        case .subagentStop(let e): e.transcriptPath
        case .userPromptSubmit(let e): e.transcriptPath
        case .preCompact(let e): e.transcriptPath
        case .postCompact(let e): e.transcriptPath
        case .postToolUseFailure(let e): e.transcriptPath
        case .stopFailure(let e): e.transcriptPath
        case .unknown: nil
        }
    }
}

// MARK: - Base fields shared by all events

private struct BaseEvent: Codable {
    let sessionId: String
    let transcriptPath: String?
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
    }
}

// MARK: - PermissionRequest  (blocks until app responds)

struct PermissionRequestEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let toolName: String
    let toolInput: JSONValue
    let permissionSuggestions: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case permissionSuggestions = "permission_suggestions"
    }
}

// MARK: - PreToolUse  (fire-and-forget, for monitoring)

struct PreToolUseEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let toolName: String
    let toolInput: JSONValue

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }
}

// MARK: - PostToolUse

struct PostToolUseEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let toolName: String
    let toolInput: JSONValue
    let toolResponse: JSONValue?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
    }
}

// MARK: - Notification

struct NotificationEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let message: String
    let title: String?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case message
        case title
        case notificationType = "notification_type"
    }
}

// MARK: - SessionStart

struct SessionStartEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let source: String?   // "startup" | "resume" | "clear" | "compact"
    let model: String?
    let cwd: String?
    let tty: String?      // injected by ClawBridge: e.g. "/dev/ttys003"

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case source
        case model
        case cwd
        case tty
    }
}

// MARK: - SessionEnd

struct SessionEndEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
    }
}

// MARK: - Stop

struct StopEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
    }
}

// MARK: - SubagentStart

struct SubagentStartEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let agentId: String
    let agentType: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case agentId = "agent_id"
        case agentType = "agent_type"
    }
}

// MARK: - SubagentStop

struct SubagentStopEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let agentId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case agentId = "agent_id"
    }
}

// MARK: - UserPromptSubmit

struct UserPromptSubmitEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let prompt: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case prompt
    }
}

// MARK: - PreCompact

struct PreCompactEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let trigger: String          // "manual" | "auto"
    let customInstructions: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case trigger
        case customInstructions = "custom_instructions"
    }
}

// MARK: - PostCompact

struct PostCompactEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let trigger: String
    let compactSummary: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case trigger
        case compactSummary = "compact_summary"
    }
}

// MARK: - PostToolUseFailure

struct PostToolUseFailureEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    let toolName: String
    let toolInput: JSONValue
    let error: String
    let isInterrupt: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case error
        case isInterrupt = "is_interrupt"
    }
}

// MARK: - StopFailure

struct StopFailureEvent: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String?
    /// "rate_limit" | "authentication_failed" | "billing_error" |
    /// "invalid_request" | "server_error" | "max_output_tokens" | "unknown"
    let error: String
    let errorDetails: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case error
        case errorDetails = "error_details"
    }
}

// MARK: - Bridge response (allow / deny for PermissionRequest)

struct HookResponse: Codable, Sendable {
    enum Decision: String, Codable, Sendable {
        case allow
        case deny
    }
    let decision: Decision
    let reason: String?
    let updatedPermissions: [JSONValue]?
}

// MARK: - JSONValue  (arbitrary JSON, avoids Any)

indirect enum JSONValue: Codable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .string(let v): return v
        case .array(let v): return "[\(v.map(\.description).joined(separator: ", "))]"
        case .object(let v):
            let pairs = v.map { "\($0.key): \($0.value.description)" }.joined(separator: ", ")
            return "{\(pairs)}"
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}
