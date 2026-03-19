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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
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
        .executableTarget(name: "SwiftLiteTesterLocalSync", dependencies: ["SwiftLite", "SwiftLiteTestModels", "SwiftLiteTestViews"]),
        .executableTarget(name: "SwiftLiteTesterWebSocketSync", dependencies: ["SwiftLite", "SwiftLiteTestModels", "SwiftLiteTestViews"]),

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
