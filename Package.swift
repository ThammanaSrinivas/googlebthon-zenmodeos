// swift-tools-version: 6.2
// ZenMode OS · the Mac app and the shared Swift packages.
//
// Open core: this repo builds on its own with the fakes in `ZenMock`. When the private repo
// (`googlebthon-zenmodeos-private`) is cloned beside this one, the app links its `ZenCorePrivate`
// package instead (Firebase, the Gemini callables). Set ZEN_USE_MOCK=1 to force the fakes.
import Foundation
import PackageDescription

let privateDir = Context.packageDirectory + "/../googlebthon-zenmodeos-private"
let usePrivate = FileManager.default.fileExists(atPath: privateDir + "/Package.swift")
    && Context.environment["ZEN_USE_MOCK"] == nil

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

var appDependencies: [Target.Dependency] = ["Albeit", "ZenAPI", "ZenMock"]
var packageDependencies: [Package.Dependency] = []
if usePrivate {
    appDependencies.append(.product(name: "ZenCorePrivate", package: "googlebthon-zenmodeos-private"))
    packageDependencies.append(.package(path: privateDir))
}

let package = Package(
    name: "ZenModeOS",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "Albeit", targets: ["Albeit"]),
        .library(name: "ZenAPI", targets: ["ZenAPI"]),
        .library(name: "ZenMock", targets: ["ZenMock"]),
        // The Mac app as a library, hosted by the Xcode app target (signed) and by `swift run`.
        .library(name: "ZenMacApp", targets: ["ZenMacApp"]),
        .executable(name: "ZenModeMac", targets: ["ZenModeMac"]),
    ],
    dependencies: packageDependencies,
    targets: [
        // Contracts and pure rules (the score, the weekly streak, the Zeno nudge schema). No UI, no network.
        .target(name: "ZenAPI", swiftSettings: swift6),
        // Fakes behind the same contracts: the open-source build and the tests run on these.
        .target(name: "ZenMock", dependencies: ["ZenAPI"], swiftSettings: swift6),
        // Albeit, the design system: tokens, type, Zeno, the lit backdrop, glass components.
        .target(name: "Albeit", swiftSettings: swift6),
        // The Mac app: the notch, onboarding, Today.
        .target(name: "ZenMacApp", dependencies: appDependencies, swiftSettings: swift6),
        // `swift run ZenModeMac`: unsigned, for fast local runs and the snapshot tour.
        .executableTarget(name: "ZenModeMac", dependencies: ["ZenMacApp"], swiftSettings: swift6),
        .testTarget(name: "ZenAPITests", dependencies: ["ZenAPI", "ZenMock"], swiftSettings: swift6),
        .testTarget(name: "AlbeitTests", dependencies: ["Albeit"], swiftSettings: swift6),
    ]
)
