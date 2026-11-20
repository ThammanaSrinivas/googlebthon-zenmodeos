// swift-tools-version: 6.2
// ZenMode OS · the shared, UI-free Swift code: the app contract, the rules, the fakes and the Mac's
// usage tracker. No SwiftUI, no backend SDK: it builds and tests on macOS and on Linux.
//
// Who depends on it:
//   - the Mac app (the root Package.swift) for every product here;
//   - the private `ZenPrivate` package, for `ZenAPI` (the contract it implements) and `ZenLogic`
//     (the same combine the server runs). It never depends on anything back, so there is no cycle.
//
//     cd Packages/ZenShared && swift test      # macOS or Linux (scripts/test-linux.sh)
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "ZenShared",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ZenAPI", targets: ["ZenAPI"]),
        .library(name: "ZenLogic", targets: ["ZenLogic"]),
        .library(name: "ZenMock", targets: ["ZenMock"]),
        .library(name: "MacUsage", targets: ["MacUsage"]),
        .library(name: "ZenVoice", targets: ["ZenVoice"]),
    ],
    targets: [
        // The one app contract: protocols, value types and the rules every surface shares (the
        // score, the weekly streak, the Zeno nudge schema, cohorts, cross-device sync). No network.
        .target(name: "ZenAPI", swiftSettings: swift6),
        // Pure rules identical to the server's: the Zen Score formula, local days, the cross-device
        // combine (lowest score wins), the name policy, and the ScoreSnapshot every device shows.
        .target(name: "ZenLogic", dependencies: ["ZenAPI"], swiftSettings: swift6),
        // Fakes behind the same contracts: the open-source build, the demo and the tests run on these.
        .target(name: "ZenMock", dependencies: ["ZenAPI", "ZenLogic"], swiftSettings: swift6),
        // The Mac's distracting-minutes tracker and its throttled publisher: a pure core plus a thin
        // AppKit adapter (behind `canImport(AppKit)`).
        .target(name: "MacUsage", dependencies: ["ZenAPI", "ZenLogic"], swiftSettings: swift6),
        // Zeno Voice: the Gemini Live protocol, Zeno's instruction and tools, the on-device ledger,
        // the toolbox, the session, the PCM maths, the offline replay and the model the notch binds
        // to. The URLSession transport and the AVAudioEngine adapter sit behind `canImport`.
        .target(name: "ZenVoice", dependencies: ["ZenAPI", "ZenLogic"],
                resources: [.copy("Resources/zeno_voice_tools_v1.json")], swiftSettings: swift6),

        .testTarget(name: "ZenAPITests", dependencies: ["ZenAPI", "ZenMock"], swiftSettings: swift6),
        .testTarget(name: "ZenLogicTests", dependencies: ["ZenLogic", "ZenAPI"],
                    resources: [.copy("Vectors")], swiftSettings: swift6),
        .testTarget(name: "ZenMockTests", dependencies: ["ZenMock", "ZenLogic", "ZenAPI"], swiftSettings: swift6),
        .testTarget(name: "ZenVoiceTests", dependencies: ["ZenVoice", "ZenMock", "ZenLogic", "ZenAPI"],
                    swiftSettings: swift6),
        .testTarget(name: "MacUsageTests", dependencies: ["MacUsage", "ZenMock", "ZenLogic", "ZenAPI"],
                    swiftSettings: swift6),
    ]
)
