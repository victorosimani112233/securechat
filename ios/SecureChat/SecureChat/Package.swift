// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SecureChat",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SecureChat",
            targets: ["SecureChat"]
        ),
    ],
    dependencies: [
        .package(path: "../SecureChatCommon"),
        .package(path: "../SecureChatCrypto"),
        .package(path: "../SecureChatStorage"),
        .package(path: "../SecureChatNetwork"),
        .package(path: "../SecureChatContacts"),
        .package(path: "../SecureChatMedia")
    ],
    targets: [
        .target(
            name: "SecureChat",
            dependencies: [
                "SecureChatCommon",
                "SecureChatCrypto",
                "SecureChatStorage",
                "SecureChatNetwork",
                "SecureChatContacts",
                "SecureChatMedia"
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "SecureChatTests",
            dependencies: ["SecureChat"],
            path: "Tests"
        ),
    ]
)