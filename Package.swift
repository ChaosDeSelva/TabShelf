// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabShelf",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TabShelf", targets: ["TabShelf"]),
        .executable(name: "TabShelfBridge", targets: ["TabShelfBridge"])
    ],
    targets: [
        .target(name: "TabShelfCore"),
        .executableTarget(name: "TabShelf", dependencies: ["TabShelfCore"]),
        .executableTarget(name: "TabShelfBridge", dependencies: ["TabShelfCore"]),
        .testTarget(name: "TabShelfCoreTests", dependencies: ["TabShelfCore"])
    ],
    swiftLanguageModes: [.v5]
)
