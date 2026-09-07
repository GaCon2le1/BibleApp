// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BibleFeedKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "BibleFeedKit", targets: ["BibleFeedKit"])
    ],
    targets: [
        .target(name: "BibleFeedKit"),
        .testTarget(name: "BibleFeedKitTests", dependencies: ["BibleFeedKit"])
    ]
)
