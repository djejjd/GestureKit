// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GestureKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GestureKitHost", targets: ["GestureKitHost"]),
        .executable(name: "TrackpadInputProbe", targets: ["TrackpadInputProbe"])
    ],
    targets: [
        .executableTarget(
            name: "GestureKitHost",
            path: "native-host/gesturekit-host/Sources/GestureKitHost"
        ),
        .testTarget(
            name: "GestureKitHostTests",
            dependencies: ["GestureKitHost"],
            path: "native-host/gesturekit-host/Tests/GestureKitHostTests"
        ),
        .executableTarget(
            name: "TrackpadInputProbe",
            path: "spikes/trackpad-input/Sources/TrackpadInputProbe"
        )
    ]
)
