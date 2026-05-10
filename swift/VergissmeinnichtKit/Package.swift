// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VergissmeinnichtKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VergissmeinnichtKit", targets: ["VergissmeinnichtKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "vergissmeinnicht_coreFFI",
            path: "VergissmeinnichtCoreFFI.xcframework"
        ),
        .target(
            name: "VergissmeinnichtKit",
            dependencies: ["vergissmeinnicht_coreFFI"],
            path: "Sources/VergissmeinnichtKit"
        ),
        .testTarget(
            name: "VergissmeinnichtKitTests",
            dependencies: ["VergissmeinnichtKit"],
            path: "Tests/VergissmeinnichtKitTests"
        ),
    ]
)
