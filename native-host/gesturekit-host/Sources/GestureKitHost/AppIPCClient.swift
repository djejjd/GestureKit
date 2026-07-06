import Foundation
import GestureKitCore
import Network

final class AppIPCClient {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port

    init(host: NWEndpoint.Host = "127.0.0.1", port: NWEndpoint.Port = 17653) {
        self.host = host
        self.port = port
    }

    func connect() -> NWConnection {
        NWConnection(host: host, port: port, using: .tcp)
    }
}
