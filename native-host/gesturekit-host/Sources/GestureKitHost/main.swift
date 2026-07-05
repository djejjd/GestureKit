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

FileHandle.standardOutput.write(NativeMessageCodec.encode(makeHostHelloResponse()))

func runStdioBridge() {
    let client = AppIPCClient()
    let connection = client.connect()
    let semaphore = DispatchSemaphore(value: 0)
    let output = BridgeOutput()

    connection.stateUpdateHandler = { state in
        if case .failed = state {
            output.set(makeAppUnavailableResponse())
            semaphore.signal()
        }
    }

    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
        if let data, !data.isEmpty {
            output.set(data)
        } else if error != nil {
            output.set(makeAppUnavailableResponse())
        }
        semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + 2)
    connection.cancel()
    FileHandle.standardOutput.write(NativeMessageCodec.encode(output.get() ?? makeAppUnavailableResponse()))
}

func makeAppUnavailableResponse() -> Data {
    Data("""
{"version":1,"id":"app-unavailable","type":"action_result","timestamp":0,"payload":{"action":"open_link_background","status":"app_unavailable"},"error":null}
""".utf8)
}

private final class BridgeOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func get() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
