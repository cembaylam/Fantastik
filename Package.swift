// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fantastik",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Fantastik",
            path: "Sources/Fantastik",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FantastikTests",
            dependencies: ["Fantastik"],
            path: "Tests/FantastikTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
