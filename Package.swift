// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacWindowCascader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacWindowCascader", targets: ["MacWindowCascader"])
    ],
    targets: [
        .executableTarget(
            name: "MacWindowCascader",
            path: "Sources/MacWindowCascader"
        )
    ]
)
