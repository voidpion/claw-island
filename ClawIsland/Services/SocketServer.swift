import Foundation

// Unix Domain Socket server — receives hook events from ClawBridge.
// Uses POSIX BSD sockets directly; each connection runs on a background thread.
//
// Protocol: [4-byte big-endian length][JSON bytes]
// Response (PermissionRequest only): [4-byte big-endian length][JSON bytes]

actor SocketServer {
    static let socketPath = "/tmp/claw-island.sock"

    private var serverFD: Int32 = -1
    private var isRunning = false
    private var eventHandler: (@MainActor (HookEvent) async -> HookResponse?)?

    func start(onEvent: @escaping @MainActor (HookEvent) async -> HookResponse?) throws {
        self.eventHandler = onEvent
        isRunning = true

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

        Task.detached(priority: .utility) { [weak self] in
            await self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        unlink(Self.socketPath)
    }

    // MARK: - Accept loop

    private func acceptLoop() async {
        while isRunning && serverFD >= 0 {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            let handler = eventHandler
            Task.detached(priority: .utility) {
                await SocketServer.handle(fd: clientFD, handler: handler)
            }
        }
    }

    // MARK: - Per-connection handler

    private static func handle(
        fd: Int32,
        handler: (@MainActor (HookEvent) async -> HookResponse?)?
    ) async {
        defer { close(fd) }

        guard let data = readLengthPrefixed(fd: fd) else { return }

        let event: HookEvent
        do {
            event = try JSONDecoder().decode(HookEvent.self, from: data)
        } catch {
            // Unknown or malformed event — ignore silently
            return
        }

        let response = await handler?(event)

        // Only PermissionRequest waits for a response
        if case .permissionRequest = event, let response,
           let bytes = try? JSONEncoder().encode(response) {
            writeLengthPrefixed(fd: fd, data: bytes)
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
