// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureChat",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SecureChat",
            targets: ["SecureChat"]),
        .library(
            name: "SecureChatCommon",
            targets: ["SecureChatCommon"]),
        .library(
            name: "SecureChatCrypto",
            targets: ["SecureChatCrypto"]),
        .library(
            name: "SecureChatNetwork",
            targets: ["SecureChatNetwork"]),
        .library(
            name: "SecureChatStorage",
            targets: ["SecureChatStorage"]),
        .library(
            name: "SecureChatMedia",
            targets: ["SecureChatMedia"]),
        .library(
            name: "SecureChatContacts",
            targets: ["SecureChatContacts"])
    ],
    dependencies: [
        .package(url: "https://github.com/signalapp/SignalProtocolKit", from: "1.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.3"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
        .package(url: "https://github.com/daltoniam/Starscream", from: "4.0.4"),
        .package(url: "https://github.com/stasel/WebRTC", from: "118.0.0")
    ],
    targets: [
        .target(
            name: "SecureChat",
            dependencies: [
                "SecureChatCommon",
                "SecureChatCrypto",
                "SecureChatNetwork",
                "SecureChatStorage",
                "SecureChatMedia",
                "SecureChatContacts"
            ],
            path: "SecureChat/SecureChat/Sources"
        ),
        .target(
            name: "SecureChatCommon",
            dependencies: [],
            path: "SecureChat/SecureChatCommon/Sources"
        ),
        .target(
            name: "SecureChatCrypto",
            dependencies: [
                "SecureChatCommon",
                .product(name: "SignalProtocolKit", package: "SignalProtocolKit")
            ],
            path: "SecureChat/SecureChatCrypto/Sources"
        ),
        .target(
            name: "SecureChatNetwork",
            dependencies: [
                "SecureChatCommon",
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "SecureChat/SecureChatNetwork/Sources"
        ),
        .target(
            name: "SecureChatStorage",
            dependencies: [
                "SecureChatCommon",
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "SecureChat/SecureChatStorage/Sources"
        ),
        .target(
            name: "SecureChatMedia",
            dependencies: [
                "SecureChatCommon"
            ],
            path: "SecureChat/SecureChatMedia/Sources"
        ),
        .target(
            name: "SecureChatContacts",
            dependencies: [
                "SecureChatCommon",
                "SecureChatStorage"
            ],
            path: "SecureChat/SecureChatContacts/Sources"
        ),
        .testTarget(
            name: "SecureChatTests",
            dependencies: ["SecureChat"]),
        .testTarget(
            name: "SecureChatCommonTests",
            dependencies: ["SecureChatCommon"]),
        .testTarget(
            name: "SecureChatCryptoTests",
            dependencies: ["SecureChatCrypto"],
            path: "SecureChat/SecureChatCrypto/Tests"),
        .testTarget(
            name: "SecureChatNetworkTests",
            dependencies: ["SecureChatNetwork"],
            path: "SecureChat/SecureChatNetwork/Tests"),
        .testTarget(
            name: "SecureChatStorageTests",
            dependencies: ["SecureChatStorage"]),
        .testTarget(
            name: "SecureChatMediaTests",
            dependencies: ["SecureChatMedia"]),
        .testTarget(
            name: "SecureChatContactsTests",
            dependencies: ["SecureChatContacts"],
            path: "SecureChat/SecureChatContacts/Tests")
    ]
)