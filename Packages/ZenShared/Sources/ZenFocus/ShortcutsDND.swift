import Foundation
import ZenAPI

/// Runs a command and answers with its exit code and output (the Mac's `Process`; a fake in tests).
public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> (code: Int32, output: String)
}

/// Mac Do Not Disturb through two Shortcuts the person adds once, both built on Set Focus:
/// "ZenMode Focus On" (Do Not Disturb on until turned off) and "ZenMode Focus Off".
public struct ShortcutsDNDHook: FocusHook {
    public static let onShortcut = "ZenMode Focus On"
    public static let offShortcut = "ZenMode Focus Off"
    public static let tool = "/usr/bin/shortcuts"

    public let id = "dnd"
    public let displayName = "Do Not Disturb"
    private let runner: any CommandRunning
    private let enabled: @Sendable () -> Bool

    public init(runner: any CommandRunning, enabled: @escaping @Sendable () -> Bool = { true }) {
        self.runner = runner
        self.enabled = enabled
    }

    /// Which of the two Shortcuts are missing ("" when both are there).
    public func missing() async -> [String] {
        guard let (code, output) = try? await runner.run(Self.tool, ["list"]), code == 0 else {
            return [Self.onShortcut, Self.offShortcut]
        }
        let names = Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        return [Self.onShortcut, Self.offShortcut].filter { !names.contains($0) }
    }

    public func status() async -> HookStatus {
        guard enabled() else { return .off }
        let gone = await missing()
        if gone.isEmpty { return .ready }
        return .needsSetup(gone.count == 2 ? "Add the two Focus Shortcuts" : "Add “\(gone[0])”")
    }

    public func onFocusStart(_ session: FocusSession) async throws {
        try await shortcut(Self.onShortcut)
    }

    public func onFocusEnd(_ session: FocusSession, kept: Bool) async throws {
        try await shortcut(Self.offShortcut)
    }

    private func shortcut(_ name: String) async throws {
        let (code, _) = try await runner.run(Self.tool, ["run", name])
        guard code == 0 else { throw HookFailure("“\(name)” didn't run") }
    }
}

#if os(macOS)
/// `Process`, off the main thread. Cancellation terminates the process.
public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(code: Int32, output: String), any Error>) in
                process.terminationHandler = { p in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: (p.terminationStatus, String(decoding: data, as: UTF8.self)))
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
#endif
