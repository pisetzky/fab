// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ChordPilotCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChordPilotCore", targets: ["ChordPilotCore"])
    ],
    targets: [
        .target(name: "ChordPilotCore"),
        .testTarget(name: "ChordPilotCoreTests", dependencies: ["ChordPilotCore"])
    ]
)
