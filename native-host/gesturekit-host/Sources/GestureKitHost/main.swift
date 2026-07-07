import Foundation
import GestureKitCore
import Network

enum GestureKitHostSelfTest {
    static func run() throws {
        let payload = Data("{\"version\":1}".utf8)
        let encoded = NativeMessageCodec.encode(payload)
        guard encoded.prefix(4) == Data([13, 0, 0, 0]) else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid length prefix"])
        }

        let decoded = try NativeMessageCodec.decode(encoded)
        guard decoded == payload else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decoded payload mismatch"])
        }

        do {
            _ = try NativeMessageCodec.decode(Data([1, 2, 3]))
            throw NSError(domain: "GestureKitHostSelfTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Too-short input did not fail"])
        } catch NativeMessageCodecError.messageTooShort {
        }

        do {
            _ = try NativeMessageCodec.decode(Data([2, 0, 0, 0, 1]))
            throw NSError(domain: "GestureKitHostSelfTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Length mismatch did not fail"])
        } catch NativeMessageCodecError.lengthMismatch(expected: 2, actual: 1) {
        }

        let hostResponse = makeHostHelloResponse()
        let framedHostResponse = NativeMessageCodec.encode(hostResponse)
        guard try NativeMessageCodec.decode(framedHostResponse) == hostResponse else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Host response frame did not decode"])
        }

        print("GestureKitHost self-test passed")
    }
}

if CommandLine.arguments.contains("--self-test") {
    do {
        try GestureKitHostSelfTest.run()
        exit(0)
    } catch {
        fputs("GestureKitHost self-test failed: \(error)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--stdio-bridge") {
    runStdioBridge()
    exit(0)
}

func makeHostHelloResponse() -> Data {
    Data("""
{"version":1,"id":"host-hello","type":"hello","timestamp":0,"payload":{"host":"GestureKitHost"},"error":null}
""".utf8)
}

runStdioBridge()

func runStdioBridge() {
    let bridge = AppToChromeBridge(connection: AppIPCClient().connect())
    bridge.start()
    bridge.wait()
}

func makeAppUnavailableResponse() -> Data {
    Data("""
{"version":1,"id":"app-unavailable","type":"action_result","timestamp":0,"payload":{"action":"open_link_background","status":"app_unavailable"},"error":null}
""".utf8)
}

private final class AppToChromeBridge: @unchecked Sendable {
    private let connection: NWConnection
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private var hasWrittenFrame = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                self.writeFrame(makeAppUnavailableResponse())
                self.done.signal()
            } else if case .cancelled = state {
                self.done.signal()
            }
        }

        receiveNext()
        startStdinReader()
        connection.start(queue: .global(qos: .userInitiated))
    }

    func wait() {
        _ = done.wait(timeout: .distantFuture)
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if error != nil {
                if !self.hasWrittenFrame {
                    self.writeFrame(makeAppUnavailableResponse())
                }
                self.done.signal()
                return
            }
            if isComplete {
                self.done.signal()
                return
            }
            self.receiveNext()
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        let lines = drainLines()
        lock.unlock()

        lines.forEach { line in
            writeFrame(line)
        }
    }

    private func drainLines() -> [Data] {
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 10) {
            let line = buffer[..<newlineIndex]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    private func writeFrame(_ payload: Data) {
        lock.lock()
        hasWrittenFrame = true
        lock.unlock()

        FileHandle.standardOutput.write(NativeMessageCodec.encode(payload))
    }

    private func startStdinReader() {
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                guard let payload = self.readNativeMessagePayload() else {
                    self.done.signal()
                    return
                }
                self.sendToApp(payload)
            }
        }
    }

    private func readNativeMessagePayload() -> Data? {
        let header = FileHandle.standardInput.readData(ofLength: 4)
        guard header.count == 4 else { return nil }
        let bytes = Array(header)
        let length =
            UInt32(bytes[0]) |
            UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 |
            UInt32(bytes[3]) << 24
        guard length > 0, length <= 1024 * 1024 else {
            fputs("GestureKitHost invalid native message length=\(length)\n", stderr)
            return nil
        }
        let payload = FileHandle.standardInput.readData(ofLength: Int(length))
        guard payload.count == Int(length) else {
            fputs("GestureKitHost truncated native message expected=\(length) actual=\(payload.count)\n", stderr)
            return nil
        }
        return payload
    }

    private func sendToApp(_ payload: Data) {
        var line = payload
        line.append(10)
        connection.send(content: line, completion: .contentProcessed { error in
            if let error {
                fputs("GestureKitHost app send failed: \(error)\n", stderr)
            }
        })
    }
}
