// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Montclair",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Montclair", targets: ["Montclair"])],
    targets: [
        .executableTarget(
            name: "Montclair",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
