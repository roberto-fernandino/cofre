// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cofre",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CofreCore"),
        .executableTarget(name: "Cofre", dependencies: ["CofreCore"]),
        .executableTarget(name: "cofre-selftest", dependencies: ["CofreCore"]),
    ]
)
