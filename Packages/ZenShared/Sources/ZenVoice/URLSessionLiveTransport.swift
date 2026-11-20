#if canImport(Darwin)
import Foundation

/// The real transport: a `URLSessionWebSocketTask` to Gemini Live. Gemini sends JSON in binary
/// frames as well as text ones; both come back as text here.
public actor URLSessionLiveTransport: LiveTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) { self.session = session }

    public func connect(to url: URL) async throws {
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1_024 * 1_024 // a long reply can carry a lot of audio
        self.task = task
        task.resume()
    }

    public func send(_ frame: String) async throws {
        guard let task else { throw URLError(.networkConnectionLost) }
        try await task.send(.string(frame))
    }

    public func receive() async throws -> String? {
        guard let task else { return nil }
        do {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: return nil
            }
        } catch {
            // A close from either side ends the stream; anything else is a dropped connection.
            #if DEBUG
            let reason = task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? ""
            FileHandle.standardError.write(Data("[voice] socket closed code=\(task.closeCode.rawValue) reason=\(reason) error=\(error)\n".utf8))
            #endif
            if task.closeCode != .invalid || self.task !== task { return nil }
            throw error
        }
    }

    public func close() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
#endif
