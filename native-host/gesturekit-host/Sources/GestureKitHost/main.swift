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
}
