// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GestureKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "GestureKitHost", targets: ["GestureKitHost"]),
        .executable(name: "TrackpadInputProbe", targets: ["TrackpadInputProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/Kyome22/OpenMultiTouchSupport.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "GestureKitHost",
            path: "native-host/gesturekit-host/Sources/GestureKitHost"
        ),
        .executableTarget(
            name: "TrackpadInputProbe",
            dependencies: [
                .product(name: "OpenMultitouchSupport", package: "OpenMultiTouchSupport")
            ],
            path: "spikes/trackpad-input/Sources/TrackpadInputProbe"
        )
    ]
)
