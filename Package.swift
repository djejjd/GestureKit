// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GestureKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "GestureKitCore", targets: ["GestureKitCore"]),
        .executable(name: "GestureKitApp", targets: ["GestureKitApp"]),
        .executable(name: "GestureKitHost", targets: ["GestureKitHost"]),
        .executable(name: "TrackpadInputProbe", targets: ["TrackpadInputProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/Kyome22/OpenMultiTouchSupport.git", branch: "main")
    ],
    targets: [
        .target(
            name: "GestureKitCore",
            path: "Sources/GestureKitCore"
        ),
        .executableTarget(
            name: "GestureKitApp",
            dependencies: [
                "GestureKitCore",
                .product(name: "OpenMultitouchSupport", package: "OpenMultiTouchSupport")
            ],
            path: "apps/macos/GestureKitApp/Sources/GestureKitApp",
            resources: [.process("menu_icon.svg")]
        ),
        .executableTarget(
            name: "GestureKitHost",
            dependencies: ["GestureKitCore"],
            path: "native-host/gesturekit-host/Sources/GestureKitHost"
        ),
        .executableTarget(
            name: "TrackpadInputProbe",
            dependencies: [
                "GestureKitCore",
                .product(name: "OpenMultitouchSupport", package: "OpenMultiTouchSupport")
            ],
            path: "spikes/trackpad-input/Sources/TrackpadInputProbe"
        ),
        .testTarget(
            name: "GestureKitCoreTests",
            dependencies: ["GestureKitCore"],
            path: "Tests/GestureKitCoreTests"
        ),
        .testTarget(
            name: "GestureKitAppTests",
            dependencies: ["GestureKitApp"],
            path: "Tests/GestureKitAppTests"
        )
    ]
)
