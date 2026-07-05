public protocol TouchBackend {
    var frames: AsyncStream<TouchFrame> { get }
    func start() -> Bool
    func stop() -> Bool
}
