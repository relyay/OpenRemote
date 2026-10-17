// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OpenRemote-Builder",
    platforms: [
        .iOS("26.0"),
    ],
    dependencies: [
        .package(name: "RootPackage", path: "../.."),
    ],
    targets: [
        .executableTarget(
    name: "OpenRemote-App",
    dependencies: [
        .product(name: "OpenRemote", package: "RootPackage"),
    ],
    linkerSettings: [
    .unsafeFlags([
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
    ]),
]
)
    ]
)
