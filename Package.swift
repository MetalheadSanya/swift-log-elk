// swift-tools-version:5.5

import PackageDescription


let package = Package(
    name: "swift-log-elk",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "LoggingELK", targets: ["LoggingELK"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMinor(from: "1.4.0")),
    ],
    targets: [
        .target(
            name: "LoggingELK",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "LoggingELKTests",
            dependencies: [
                .target(name: "LoggingELK")
            ]
        )
    ]
)
