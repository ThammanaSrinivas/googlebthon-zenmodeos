// The shared vector files in Vectors/, as the replay tests read them.
import Foundation

enum Vectors {
    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Vectors/\(name) is missing" }
    }

    /// Vectors/<name>, from the test bundle's resources (or next to this file when run from source).
    static func url(_ name: String) -> URL? {
        if let url = Bundle.module.url(forResource: "Vectors/\(name)", withExtension: nil)
            ?? Bundle.module.resourceURL?.appendingPathComponent("Vectors").appendingPathComponent(name),
            FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Vectors").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    static func load(_ name: String) throws -> [String: Any] {
        guard let url = url(name) else { throw Missing(name: name) }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }
}
