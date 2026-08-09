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
        .executable(name: "TrackpadInputProbe", targets: ["TrackpadInputProbe"]),
        .executable(name: "ProviderIPCProbe", targets: ["ProviderIPCProbe"]),
        .executable(name: "CleanTCCProbe", targets: ["CleanTCCProbe"]),
        .executable(name: "InteractionShieldProbe", targets: ["InteractionShieldProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/Kyome22/OpenMultiTouchSupport.git", branch: "main")
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "GestureKitCore",
            dependencies: ["CSQLite"],
            path: "Sources/GestureKitCore"
        ),
        .executableTarget(
            name: "GestureKitApp",
            dependencies: [
                "GestureKitCore",
                .product(name: "OpenMultitouchSupport", package: "OpenMultiTouchSupport")
            ],
            path: "apps/macos/GestureKitApp/Sources/GestureKitApp"
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
        .executableTarget(
            name: "ProviderIPCProbe",
            dependencies: ["GestureKitCore"],
            path: "spikes/provider-ipc/Sources/ProviderIPCProbe"
        ),
        .executableTarget(
            name: "CleanTCCProbe",
            path: "spikes/clean-tcc/Sources/CleanTCCProbe"
        ),
        .executableTarget(
            name: "InteractionShieldProbe",
            path: "spikes/interaction-shield/Sources/InteractionShieldProbe"
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
