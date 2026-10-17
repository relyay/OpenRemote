// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpenRemote",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "OpenRemote",
            targets: ["OpenRemote"]
        ),
    ],
    targets: [
        .target(
            name: "OpenRemote"
        ),
    ]
)
