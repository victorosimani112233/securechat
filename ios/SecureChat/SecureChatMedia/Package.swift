// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SecureChatMedia",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "SecureChatMedia",
            targets: ["SecureChatMedia"]
        )
    ],
    dependencies: [
        // WebRTC iOS SDK
        .package(
            url: "https://github.com/stasel/WebRTC.git",
            .upToNextMajor(from: "120.0.0")
        ),
        // Local modules
        .package(path: "../SecureChatCommon"),
        .package(path: "../SecureChatNetwork")
    ],
    targets: [
        .target(
            name: "SecureChatMedia",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                "SecureChatCommon",
                "SecureChatNetwork"
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "SecureChatMediaTests",
            dependencies: [
                "SecureChatMedia",
                "SecureChatCommon",
                "SecureChatNetwork"
            ],
            path: "Tests"
        )
    ]
)