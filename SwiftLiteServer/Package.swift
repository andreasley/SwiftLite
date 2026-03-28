// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftLiteServer",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .macCatalyst(.v26)],
    products: [
        .executable(
            name: "SwiftLiteWebSyncServer",
            targets: ["SwiftLiteWebSyncServer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.21.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket", from: "2.6.0"),
        .package(path: "../SwiftLiteShared")
    ],
    targets: [
        .executableTarget(
            name: "SwiftLiteWebSyncServer",
            dependencies: [
            	"SwiftLiteShared",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
    ]
)
