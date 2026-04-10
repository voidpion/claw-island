// CodexBridge — called by OpenAI Codex CLI hooks.
// Codex writes the hook event JSON to stdin; this binary
// forwards it to ClawIsland over a Unix domain socket.
// No blocking — Codex hooks currently have no PermissionRequest.
//
// Socket protocol: [4-byte big-endian length][JSON bytes]

import Foundation

let socketPath = "/tmp/claw-island.sock"

// 1. Read all stdin
var inputData = FileHandle.standardInput.readDataToEndOfFile()

guard !inputData.isEmpty,
      var json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let eventName = json["hook_event_name"] as? String
else { exit(0) }

// Inject agent type so SessionManager can distinguish source
json["agent"] = "codex"

// Inject tty via sysctl kp_eproc.e_tdev
var kinfo = kinfo_proc()
var kinfoSize = MemoryLayout<kinfo_proc>.size
var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
if sysctl(&mib, 4, &kinfo, &kinfoSize, nil, 0) == 0 {
    let dev = kinfo.kp_eproc.e_tdev
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
    close(sock)
    exit(0)
}

// 3. Send length-prefixed payload
guard sendData(sock: sock, data: inputData) else { close(sock); exit(0) }

// No response expected — Codex hooks are fire-and-forget
close(sock)
exit(0)

// MARK: - Logging

func writeLog(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/codex-bridge.log")
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
