// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftLiteShared",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .macCatalyst(.v26)],
    products: [
        .library(
            name: "SwiftLiteShared",
            targets: ["SwiftLiteShared"]
        ),
    ],
    targets: [
        .target(name: "SwiftLiteShared"),
    ]
)
