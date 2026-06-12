// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "tokenbar", targets: ["TokenBar"])
    ],
    targets: [
        .executableTarget(
            name: "TokenBar",
            path: "Sources/TokenBar",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
