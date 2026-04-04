import Foundation

// Unix Domain Socket server — receives hook events from ClawBridge.
// Uses POSIX BSD sockets directly; each connection runs on a background thread.
//
// Protocol: [4-byte big-endian length][JSON bytes]
// Response (PermissionRequest only): [4-byte big-endian length][JSON bytes]
//
// Important: accept() is a blocking POSIX call. It MUST run on a real OS thread
// (Thread.detachNewThread), NOT inside Swift's cooperative async task system.
// Putting it in Task.detached / actor async methods blocks the cooperative thread
// pool, causing the socket to appear bound but never accept connections.

final class SocketServer: @unchecked Sendable {
    static let socketPath = "/tmp/claw-island.sock"

    private var serverFD: Int32 = -1
    private var eventHandler: (@MainActor (HookEvent) async -> HookResponse?)?

    func start(onEvent: @escaping @MainActor (HookEvent) async -> HookResponse?) throws {
        self.eventHandler = onEvent

        unlink(Self.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENOTSUP) }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            Self.socketPath.withCString { cstr in
                UnsafeMutableRawPointer(ptr).copyMemory(from: cstr, byteCount: strlen(cstr) + 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        guard listen(fd, 16) == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }

        Self.log("socket listening on \(Self.socketPath), fd=\(fd)")

        // Run the blocking accept() loop on a dedicated OS thread — never in Swift concurrency.
        let handler = onEvent
        Thread.detachNewThread {
            Self.acceptLoop(serverFD: fd, handler: handler)
        }
    }

    func stop() {
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        unlink(Self.socketPath)
    }

    // MARK: - Accept loop (OS thread)

    private static func acceptLoop(
        serverFD: Int32,
        handler: @escaping @MainActor (HookEvent) async -> HookResponse?
    ) {
        log("acceptLoop started fd=\(serverFD)")
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                log("acceptLoop: accept failed errno=\(errno)")
                break
            }
            log("accepted clientFD=\(clientFD)")
            Task.detached(priority: .utility) {
                await Self.handle(fd: clientFD, handler: handler)
            }
        }
        log("acceptLoop exited")
    }

    // MARK: - Per-connection handler

    private static func handle(
        fd: Int32,
        handler: @escaping @MainActor (HookEvent) async -> HookResponse?
    ) async {
        defer { close(fd) }

        guard let data = readLengthPrefixed(fd: fd) else {
            log("readLengthPrefixed failed fd=\(fd)")
            return
        }

        log("received \(data.count) bytes")
        log("raw: \(String(data: data, encoding: .utf8) ?? "<binary>")")

        let event: HookEvent
        do {
            event = try JSONDecoder().decode(HookEvent.self, from: data)
            log("decoded sessionId=\(event.sessionId)")
        } catch {
            log("decode error: \(error)")
            return
        }

        log("calling handler...")
        let response = await handler(event)
        log("handler returned, response=\(response != nil ? "yes" : "nil")")

        // PermissionRequest and permission_prompt Notification both wait for a response
        let needsResponse: Bool
        if case .permissionRequest = event {
            needsResponse = true
        } else if case .notification(let n) = event, n.notificationType == "permission_prompt" {
            needsResponse = true
        } else {
            needsResponse = false
        }

        if needsResponse, let response,
           let bytes = try? JSONEncoder().encode(response) {
            writeLengthPrefixed(fd: fd, data: bytes)
        }
    }

    // MARK: - Debug log (writes to /tmp/claw-island.log for diagnosis)

    private static func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/claw-island.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - I/O

    private static func readLengthPrefixed(fd: Int32) -> Data? {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        guard readExact(fd: fd, buf: &lenBuf, count: 4) else { return nil }
        let length = Int(UInt32(bigEndian: lenBuf.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length > 0, length < 10_000_000 else { return nil }
        var buf = [UInt8](repeating: 0, count: length)
        guard readExact(fd: fd, buf: &buf, count: length) else { return nil }
        return Data(buf)
    }

    private static func readExact(fd: Int32, buf: inout [UInt8], count: Int) -> Bool {
        var received = 0
        while received < count {
            let n = buf.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + received, count - received)
            }
            if n <= 0 { return false }
            received += n
        }
        return true
    }

    private static func writeLengthPrefixed(fd: Int32, data: Data) {
        var length = UInt32(data.count).bigEndian
        var payload = Data(bytes: &length, count: 4)
        payload.append(data)
        payload.withUnsafeBytes { ptr in
            var sent = 0
            while sent < payload.count {
                let n = write(fd, ptr.baseAddress! + sent, payload.count - sent)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}
