// swift-tools-version: 6.2
// ZenMode OS · the Mac app.
//
// The shared, UI-free code (the ZenAPI contract, ZenLogic, the ZenMock fakes, MacUsage) is its own
// package in Packages/ZenShared, so the private backend package can depend on it too without a cycle:
//
//     ZenModeMac ──▶ ZenShared ◀── ZenPrivate (private repo, optional)
//          └──────────────────────────▲
//
// Open core: this repo builds on its own with the fakes in `ZenMock`. When the private repo
// (`googlebthon-zenmodeos-private`) is cloned beside this one, the app links its `ZenPrivate`
// package instead (the live backend, the Gemini callables). Set ZEN_USE_MOCK=1 to force the fakes.
import Foundation
import PackageDescription

let privateDir = Context.packageDirectory + "/../googlebthon-zenmodeos-private/ZenPrivate"
#if os(Linux)
// The app is SwiftUI (macOS only), and ZenPrivate offers only its logic product on Linux: resolve
// on the fakes there, so the manifest still loads.
let usePrivate = false
#else
let usePrivate = FileManager.default.fileExists(atPath: privateDir + "/Package.swift")
    && Context.environment["ZEN_USE_MOCK"] == nil
#endif

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

func shared(_ product: String) -> Target.Dependency { .product(name: product, package: "ZenShared") }

var appDependencies: [Target.Dependency] = ["Albeit", shared("ZenAPI"), shared("ZenLogic"), shared("ZenMock"), shared("MacUsage")]
var packageDependencies: [Package.Dependency] = [.package(path: "Packages/ZenShared")]
if usePrivate {
    appDependencies.append(.product(name: "ZenPrivate", package: "ZenPrivate"))
    packageDependencies.append(.package(path: privateDir))
}

let package = Package(
    name: "ZenModeOS",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "Albeit", targets: ["Albeit"]),
        .executable(name: "ZenModeMac", targets: ["ZenModeMac"]),
    ],
    dependencies: packageDependencies,
    targets: [
        // Albeit, the design system: tokens, type, Zeno, the lit backdrop, glass components.
        .target(name: "Albeit", swiftSettings: swift6),
        // The Mac app: the notch, onboarding, Today.
        .executableTarget(name: "ZenModeMac", dependencies: appDependencies, swiftSettings: swift6),
        .testTarget(name: "AlbeitTests", dependencies: ["Albeit"], swiftSettings: swift6),
    ]
)
