// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftLite",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .macCatalyst(.v26)],
    products: [
        .library(
            name: "SwiftLite",
            targets: ["SwiftLite"]
        ),
        .library(
            name: "SwiftLiteTestModels",
            targets: ["SwiftLiteTestModels"]
        ),
        .library(
            name: "SwiftLiteTestViews",
            targets: ["SwiftLiteTestViews"]
        ),
        .executable(
            name: "SwiftLiteTesterHeadless",
            targets: ["SwiftLiteTesterHeadless"]
        ),
        .executable(
            name: "SwiftLiteWebSyncServer",
            targets: ["SwiftLiteWebSyncServer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.21.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket", from: "2.6.0"),
    ],
    targets: [
        .macro(
            name: "SwiftLiteMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),

        .target(name: "SwiftLite", dependencies: ["SwiftLiteMacros"]),
        .target(name: "SwiftLiteTestModels", dependencies: ["SwiftLite"]),
        .target(name: "SwiftLiteTestViews", dependencies: ["SwiftLite", "SwiftLiteTestModels"]),

        .executableTarget(name: "SwiftLiteTesterHeadless", dependencies: ["SwiftLite", "SwiftLiteTestModels"]),
        .executableTarget(name: "SwiftLiteTesterLocal", dependencies: ["SwiftLite", "SwiftLiteTestModels", "SwiftLiteTestViews"]),
        .executableTarget(name: "SwiftLiteInMemorySyncTester", dependencies: ["SwiftLite", "SwiftLiteTestModels", "SwiftLiteTestViews"]),
        .executableTarget(name: "SwiftLiteWebSyncTester", dependencies: ["SwiftLite", "SwiftLiteTestModels", "SwiftLiteTestViews"]),

        .executableTarget(
            name: "SwiftLiteWebSyncServer",
            dependencies: [
                "SwiftLite",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "SwiftLiteTests",
            dependencies: [
                "SwiftLiteMacros",
                "SwiftLite",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
