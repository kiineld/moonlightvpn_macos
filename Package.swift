// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Moonlight",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "Moonlight", targets: ["Moonlight"]),
        .executable(name: "moonlight-helper", targets: ["MoonlightHelper"]),
        .executable(name: "moonlight-tests", targets: ["MoonlightTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "MoonlightDesign",
            path: "Sources/MoonlightDesign"
        ),
        .target(
            name: "MoonlightCore",
            dependencies: ["Yams"],
            path: "Sources/MoonlightCore"
        ),
        .executableTarget(
            name: "Moonlight",
            dependencies: ["MoonlightCore", "MoonlightDesign"],
            path: "Sources/Moonlight"
        ),
        .executableTarget(
            name: "MoonlightHelper",
            path: "Sources/MoonlightHelper"
        ),
        // A plain executable rather than a `.testTarget`: XCTest ships with
        // Xcode, not with the Command Line Tools, and the whole point of this
        // package is that it builds and verifies with the Tools alone.
        //
        //     swift run moonlight-tests
        .executableTarget(
            name: "MoonlightTests",
            dependencies: ["MoonlightCore", "Yams"],
            path: "Tests/MoonlightCoreTests"
        ),
    ]
)
