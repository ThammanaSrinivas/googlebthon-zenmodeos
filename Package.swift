// swift-tools-version: 6.2
// ZenMode OS · the Mac app.
//
// The shared, UI-free code (the ZenAPI contract, ZenLogic, the ZenMock fakes, MacUsage) is its own
// package in Packages/ZenShared, so the private backend package can depend on it too without a cycle:
//
//     ZenMacApp ──▶ ZenShared ◀── ZenCorePrivate (private repo, optional)
//          └───────────────────────────▲
//
// Open core: this repo builds on its own with the fakes in `ZenMock`. When the private repo
// (`googlebthon-zenmodeos-private`) is cloned beside this one, the app links its `ZenCorePrivate`
// package instead (Firebase, the Gemini callables). Set ZEN_USE_MOCK=1 to force the fakes.
import Foundation
import PackageDescription

let privateDir = Context.packageDirectory + "/../googlebthon-zenmodeos-private"
#if os(Linux)
// The app is SwiftUI (macOS only), and the private package offers only its logic on Linux: resolve
// on the fakes there, so the manifest still loads (CI tests Packages/ZenShared).
let usePrivate = false
#else
let usePrivate = FileManager.default.fileExists(atPath: privateDir + "/Package.swift")
    && Context.environment["ZEN_USE_MOCK"] == nil
#endif

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

func shared(_ product: String) -> Target.Dependency { .product(name: product, package: "ZenShared") }

var appDependencies: [Target.Dependency] = ["Albeit", shared("ZenAPI"), shared("ZenLogic"), shared("ZenMock"), shared("MacUsage"), shared("ZenVoice")]
var phoneDependencies: [Target.Dependency] = ["Albeit", shared("ZenAPI"), shared("ZenLogic"), shared("ZenMock"), shared("ZenVoice")]
var packageDependencies: [Package.Dependency] = [.package(path: "Packages/ZenShared")]
if usePrivate {
    appDependencies.append(.product(name: "ZenCorePrivate", package: "googlebthon-zenmodeos-private"))
    phoneDependencies.append(.product(name: "ZenCorePrivate", package: "googlebthon-zenmodeos-private"))
    packageDependencies.append(.package(path: privateDir))
}

let package = Package(
    name: "ZenModeOS",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "Albeit", targets: ["Albeit"]),
        // The Mac app as a library, hosted by the Xcode app target (signed) and by `swift run`.
        // ZenAPI and ZenMock come from Packages/ZenShared (the Xcode project references it too).
        .library(name: "ZenMacApp", targets: ["ZenMacApp"]),
        .executable(name: "ZenModeMac", targets: ["ZenModeMac"]),
        // The iPhone app as a library, hosted by the Xcode iPhone target. It carries the private
        // backend the same way ZenMacApp does, so the public Xcode project never names it.
        .library(name: "ZenPhoneApp", targets: ["ZenPhoneApp"]),
    ],
    dependencies: packageDependencies,
    targets: [
        // Albeit, the design system: tokens, type, Zeno, the lit backdrop, glass components.
        .target(name: "Albeit", swiftSettings: swift6),
        // The Mac app: the notch, onboarding, Today.
        .target(name: "ZenMacApp", dependencies: appDependencies, swiftSettings: swift6),
        // `swift run ZenModeMac`: unsigned, for fast local runs and the snapshot tour.
        .executableTarget(name: "ZenModeMac", dependencies: ["ZenMacApp"], swiftSettings: swift6),
        // The iPhone app: sign-in, the live score, approving a Mac.
        .target(name: "ZenPhoneApp", dependencies: phoneDependencies, swiftSettings: swift6),
        .testTarget(name: "AlbeitTests", dependencies: ["Albeit"], swiftSettings: swift6),
        .testTarget(name: "ZenMacAppTests", dependencies: ["ZenMacApp", shared("ZenAPI")], swiftSettings: swift6),
    ]
)
