// swift-tools-version: 6.4

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-algebra-derivation",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Algebra Derivation", targets: ["Algebra Derivation"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-foundations/swift-witness-derivation.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "602.0.0"..<"603.0.0"
        ),
    ],
    targets: [
        .macro(
            name: "Algebra Derivation Macros",
            dependencies: [
                .product(name: "Witness Derivation Core", package: "swift-witness-derivation"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Algebra Derivation",
            dependencies: ["Algebra Derivation Macros"]
        ),
        .testTarget(
            name: "Algebra Derivation Tests",
            dependencies: ["Algebra Derivation"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
