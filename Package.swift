// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sift",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "SiftApp",
            targets: ["SiftApp"]
        ),
    ],
    targets: [
        .target(
            name: "SiftCore"
        ),
        .target(
            name: "DuckDBAdapter",
            dependencies: ["SiftCore"]
        ),
        .target(
            name: "SiftMetal",
            dependencies: ["SiftCore"],
            exclude: ["Shaders"]
        ),
        .target(
            name: "SiftKit",
            dependencies: ["SiftCore", "DuckDBAdapter", "SiftMetal"]
        ),
        .executableTarget(
            name: "SiftApp",
            dependencies: ["SiftKit"]
        ),
        .testTarget(
            name: "SiftCoreTests",
            dependencies: ["SiftCore"]
        ),
        .testTarget(
            name: "DuckDBAdapterTests",
            dependencies: ["DuckDBAdapter", "SiftCore"]
        ),
        .testTarget(
            name: "SiftMetalTests",
            dependencies: ["SiftMetal", "SiftCore"]
        ),
        .testTarget(
            name: "SiftKitTests",
            dependencies: ["SiftKit", "SiftMetal", "SiftCore", "DuckDBAdapter"]
        ),
    ]
)
