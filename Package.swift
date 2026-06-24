// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SDForensics",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SDForensics", targets: ["SDForensics"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SDForensics",
            dependencies: [],
            path: "Sources/SDForensics"
        )
    ]
)
