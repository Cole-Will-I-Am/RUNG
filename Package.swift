// swift-tools-version:5.9
//
// LOCAL / CI ENGINE VERIFICATION ONLY — this package is NOT part of the iOS app build
// (the app is built from project.yml by XcodeGen). It compiles the pure-Foundation
// engine in RUNG/Sources/Core as the `RungCore` module so the scoring, multiplier,
// bank/push, deterministic board generation, and dictionary logic can be unit-tested
// with `swift test` on any machine — no Xcode required. The exact same source files are
// compiled into the iOS app target (module `RUNG`).
import PackageDescription

let package = Package(
    name: "RungCore",
    products: [
        .library(name: "RungCore", targets: ["RungCore"]),
    ],
    targets: [
        .target(
            name: "RungCore",
            path: "RUNG/Sources/Core"
        ),
        .testTarget(
            name: "RungCoreTests",
            dependencies: ["RungCore"],
            path: "CoreTests"
        ),
    ]
)
