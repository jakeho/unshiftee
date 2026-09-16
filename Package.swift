// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Unshiftee",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Unshiftee", targets: ["Unshiftee"]),
    ],
    targets: [
        .executableTarget(
            name: "Unshiftee",
            path: "Sources/Unshiftee"
        ),
    ]
)
