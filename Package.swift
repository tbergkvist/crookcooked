// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Crookcooked",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrookcookedCore", targets: ["CrookcookedCore"]),
        .executable(name: "CrookcookedMac", targets: ["CrookcookedMac"]),
    ],
    targets: [
        .target(
            name: "CrookcookedCore",
            path: "Sources/CrookcookedCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CrookcookedMac",
            dependencies: ["CrookcookedCore"],
            path: "Apps/Mac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CrookcookedCoreChecks",
            dependencies: ["CrookcookedCore"],
            path: "Checks/CrookcookedCoreChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CrookcookedCoreTests",
            dependencies: ["CrookcookedCore"],
            path: "Tests/CrookcookedCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
