// ClawBridge — called by Claude Code hooks.
// Claude Code writes the hook event JSON to stdin; this binary
// forwards it to ClawIsland over a Unix domain socket.
// For PermissionRequest, it blocks and waits for the allow/deny decision.
//
// Socket protocol: [4-byte big-endian length][JSON bytes]

import Foundation

let socketPath = "/tmp/claw-island.sock"

// 1. Read all stdin (readDataToEndOfFile blocks until EOF — correct for a hook pipe)
var inputData = FileHandle.standardInput.readDataToEndOfFile()

guard !inputData.isEmpty,
      var json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let eventName = json["hook_event_name"] as? String
else { exit(0) }

// Inject tty via sysctl kp_eproc.e_tdev — works even when all stdio fds are redirected by Claude Code.
var kinfo = kinfo_proc()
var kinfoSize = MemoryLayout<kinfo_proc>.size
var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
if sysctl(&mib, 4, &kinfo, &kinfoSize, nil, 0) == 0 {
    let dev = kinfo.kp_eproc.e_tdev   // dev_t of controlling terminal
    if dev != 0 && dev != -1, let ptr = devname(dev, S_IFCHR) {
        json["tty"] = "/dev/" + String(cString: ptr)
    }
}
if let modified = try? JSONSerialization.data(withJSONObject: json) { inputData = modified }

// 2. Connect to ClawIsland socket
let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { exit(0) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    socketPath.withCString { cstr in
        UnsafeMutableRawPointer(ptr).copyMemory(from: cstr, byteCount: strlen(cstr) + 1)
    }
}

let connectResult = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connectResult == 0 else {
    // ClawIsland not running — let the tool proceed transparently
    close(sock)
    exit(0)
}

// 3. Send length-prefixed payload
guard sendData(sock: sock, data: inputData) else { close(sock); exit(0) }

// 4. For PermissionRequest / permission_prompt Notification: wait for decision
let isPermissionEvent = eventName == "PermissionRequest"
    || (eventName == "Notification"
        && (json["notification_type"] as? String) == "permission_prompt")

if isPermissionEvent {
    if let responseData = receiveData(sock: sock),
       let response = try? JSONDecoder().decode(BridgeResponse.self, from: responseData) {
        let raw = String(data: responseData, encoding: .utf8) ?? "?"
        writeLog("claw-bridge: received response: \(raw), decision=\(response.decision)")
        close(sock)

        // Claude Code expects (per official docs):
        // {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
        // {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"..."}}}
        let behavior: String
        var message: String? = nil
        if response.decision == "allow" {
            behavior = "allow"
        } else {
            behavior = "deny"
            message = "Denied by user"
        }

        var decisionObj: [String: Any] = ["behavior": behavior]
        if let msg = message {
            decisionObj["message"] = msg
        }
        if let perms = response.updatedPermissions?.value {
            decisionObj["updatedPermissions"] = perms
        }
        let stdoutObj: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionObj
            ]
        ]

        if let stdoutData = try? JSONSerialization.data(withJSONObject: stdoutObj) {
            let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? "?"
            writeLog("claw-bridge: writing to stdout: \(stdoutStr)")
            FileHandle.standardOutput.write(stdoutData)
        }
        exit(0)
    }
    // On timeout/error, allow by default
    writeLog("claw-bridge: ERROR — no response received, defaulting to allow")
    close(sock)
    exit(0)
}

close(sock)
exit(0)

// MARK: - Logging

func writeLog(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/claw-bridge.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - I/O helpers

func sendData(sock: Int32, data: Data) -> Bool {
    var length = UInt32(data.count).bigEndian
    var payload = Data(bytes: &length, count: 4)
    payload.append(data)
    var sent = 0
    let result = payload.withUnsafeBytes { ptr -> Bool in
        while sent < payload.count {
            let n = write(sock, ptr.baseAddress! + sent, payload.count - sent)
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
    return result
}

func receiveData(sock: Int32) -> Data? {
    var lenBuf = [UInt8](repeating: 0, count: 4)
    guard readExact(sock: sock, buf: &lenBuf, count: 4) else { return nil }
    let length = Int(UInt32(bigEndian: lenBuf.withUnsafeBytes { $0.load(as: UInt32.self) }))
    guard length > 0, length < 10_000_000 else { return nil }
    var buf = [UInt8](repeating: 0, count: length)
    guard readExact(sock: sock, buf: &buf, count: length) else { return nil }
    return Data(buf)
}

func readExact(sock: Int32, buf: inout [UInt8], count: Int) -> Bool {
    var received = 0
    while received < count {
        let n = buf.withUnsafeMutableBytes { ptr in
            read(sock, ptr.baseAddress! + received, count - received)
        }
        if n <= 0 { return false }
        received += n
    }
    return true
}

struct BridgeResponse: Decodable {
    let decision: String   // "allow" | "deny"
    let updatedPermissions: AnyJSON?  // arbitrary JSON array
}

/// Wraps arbitrary JSON for Codable — used to pass updatedPermissions through.
struct AnyJSON: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyJSON].self) { value = v.map(\.value) }
        else if let v = try? c.decode([String: AnyJSON].self) { value = v.mapValues(\.value) }
        else { value = NSNull() }
    }
}
