// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "osaurus-contacts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "osaurus-contacts", type: .dynamic, targets: ["osaurus_contacts"])
    ],
    targets: [
        .target(
            name: "osaurus_contacts",
            path: "Sources/osaurus_contacts"
        )
    ]
)