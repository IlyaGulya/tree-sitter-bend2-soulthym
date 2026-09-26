// swift-tools-version:5.3

import Foundation
import PackageDescription

var sources = ["src/parser.c"]
if FileManager.default.fileExists(atPath: "src/scanner.c") {
    sources.append("src/scanner.c")
}

let package = Package(
    name: "TreeSitterBend2",
    products: [
        .library(name: "TreeSitterBend2", targets: ["TreeSitterBend2"]),
    ],
    dependencies: [
        .package(name: "SwiftTreeSitter", url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "TreeSitterBend2",
            dependencies: [],
            path: ".",
            sources: sources,
            resources: [
                .copy("queries")
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .testTarget(
            name: "TreeSitterBend2Tests",
            dependencies: [
                "SwiftTreeSitter",
                "TreeSitterBend2",
            ],
            path: "bindings/swift/TreeSitterBend2Tests"
        )
    ],
    cLanguageStandard: .c11
)
