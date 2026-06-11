// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoldPrice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GoldPrice", targets: ["GoldPrice"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3")
    ],
    targets: [
        .target(
            name: "GoldPriceCore",
            path: "Sources/GoldPriceCore"
        ),
        .executableTarget(
            name: "GoldPrice",
            dependencies: ["GoldPriceCore"],
            path: "Sources/GoldPrice"
        ),
        .testTarget(
            name: "GoldPriceCoreTests",
            dependencies: [
                "GoldPriceCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/GoldPriceCoreTests"
        )
    ]
)
