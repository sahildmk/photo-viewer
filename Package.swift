// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PhotoViewer",
            path: "Sources/PhotoViewer",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        )
    ]
)
