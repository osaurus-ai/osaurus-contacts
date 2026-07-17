// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "osaurus-contacts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "osaurus-contacts", type: .dynamic, targets: ["osaurus_contacts"])
    ],
    dependencies: [
        .package(url: "https://github.com/osaurus-ai/osaurus-plugin-sdk.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "osaurus_contacts",
            dependencies: [
                .product(name: "OsaurusPluginABI", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Sources/osaurus_contacts"
        ),
        .testTarget(
            name: "osaurus_contactsTests",
            dependencies: [
                "osaurus_contacts",
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Tests/osaurus_contactsTests"
        )
    ]
)