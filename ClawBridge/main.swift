// ClawBridge — called by Claude Code hooks.
// Claude Code writes the hook event JSON to stdin; this binary
// forwards it to ClawIsland over a Unix domain socket.
// For PermissionRequest, it blocks and waits for the allow/deny decision.
//
// Socket protocol: [4-byte big-endian length][JSON bytes]

import Foundation

let socketPath = "/tmp/claw-island.sock"

// 1. Read all stdin
var inputData = Data()
let stdin = FileHandle.standardInput
while true {
    let chunk = stdin.availableData
    if chunk.isEmpty { break }
    inputData.append(chunk)
}

guard !inputData.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let eventName = json["hook_event_name"] as? String
else { exit(0) }

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
        close(sock)
        // Exit 2 = deny; 0 = allow
        exit(response.decision == "allow" ? 0 : 2)
    }
    // On timeout/error, allow by default
    close(sock)
    exit(0)
}

close(sock)
exit(0)

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
}
