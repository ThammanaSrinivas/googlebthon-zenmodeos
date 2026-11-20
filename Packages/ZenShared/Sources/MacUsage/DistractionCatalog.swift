// Which apps and sites count as distracting on a computer: only their time counts against the
// promise. Ported from the ZenMode OS desktop app's shipped lists (social, video and games are
// distracting; work, study, chat, mail and music are not). People can move apps either way, except
// the locked feeds, which always count.
import Foundation

public struct DistractionCatalog: Sendable, Equatable, Codable {
    /// A site recognised from a browser window's title (when the adapter can read titles).
    public struct Site: Sendable, Equatable, Codable {
        public let id: String
        public let name: String
        /// Lowercase markers looked for in the title.
        public let titleMarkers: [String]
        public var key: String { "web:\(id)" }
    }

    /// The feeds no one can mark as fine: their sites always count.
    public static let lockedDistracting: Set<String> = [
        "web:youtube", "web:instagram", "web:facebook", "web:reddit", "web:x", "web:tiktok",
    ]

    /// Shipped distracting ids: lowercase macOS bundle ids and site keys.
    public static let shippedDistracting: Set<String> = lockedDistracting.union([
        // streaming and video sites
        "web:netflix", "web:primevideo", "web:hotstar", "web:twitch", "web:disneyplus", "web:hulu",
        "web:crunchyroll", "web:9gag", "web:tumblr", "web:bluesky",
        // video players and streaming apps on macOS
        "org.videolan.vlc", "io.mpv", "com.colliderli.iina", "com.apple.tv",
        // games and their stores on macOS
        "com.valvesoftware.steam", "com.epicgames.epicgameslauncher", "com.gog.galaxy",
        "com.mojang.minecraftlauncher", "com.roblox.robloxplayer",
    ])

    /// macOS browsers, whose time is decided by the site in front, not the browser.
    public static let browsers: Set<String> = [
        "org.mozilla.firefox", "com.google.chrome", "com.microsoft.edgemac", "com.brave.browser",
        "com.apple.safari", "company.thebrowser.browser", "com.operasoftware.opera", "com.kagi.kagimacos",
        "com.vivaldi.vivaldi", "app.zen-browser.zen",
    ]

    /// Sites recognised from a browser title: the distracting feeds and the work sites that
    /// shouldn't be mistaken for them.
    public static let sites: [Site] = [
        Site(id: "youtube", name: "YouTube", titleMarkers: ["youtube"]),
        Site(id: "instagram", name: "Instagram", titleMarkers: ["instagram"]),
        Site(id: "facebook", name: "Facebook", titleMarkers: ["facebook"]),
        Site(id: "reddit", name: "Reddit", titleMarkers: ["reddit"]),
        Site(id: "x", name: "X", titleMarkers: [" / x", "twitter"]),
        Site(id: "tiktok", name: "TikTok", titleMarkers: ["tiktok"]),
        Site(id: "netflix", name: "Netflix", titleMarkers: ["netflix"]),
        Site(id: "primevideo", name: "Prime Video", titleMarkers: ["prime video"]),
        Site(id: "hotstar", name: "JioHotstar", titleMarkers: ["hotstar"]),
        Site(id: "twitch", name: "Twitch", titleMarkers: ["twitch"]),
        Site(id: "github", name: "GitHub", titleMarkers: ["github"]),
        Site(id: "googledocs", name: "Google Docs", titleMarkers: ["google docs", "google sheets", "google slides"]),
        Site(id: "notion", name: "Notion", titleMarkers: ["notion"]),
        Site(id: "figma", name: "Figma", titleMarkers: ["figma"]),
        Site(id: "stackoverflow", name: "Stack Overflow", titleMarkers: ["stack overflow"]),
        Site(id: "disneyplus", name: "Disney+", titleMarkers: ["disney+"]),
        Site(id: "hulu", name: "Hulu", titleMarkers: ["hulu"]),
        Site(id: "crunchyroll", name: "Crunchyroll", titleMarkers: ["crunchyroll"]),
        Site(id: "9gag", name: "9GAG", titleMarkers: ["9gag"]),
        Site(id: "tumblr", name: "Tumblr", titleMarkers: ["tumblr"]),
        Site(id: "bluesky", name: "Bluesky", titleMarkers: ["bluesky"]),
        Site(id: "leetcode", name: "LeetCode", titleMarkers: ["leetcode"]),
    ]

    /// The person's choices: true marks an id distracting, false marks it fine.
    public private(set) var overrides: [String: Bool]

    public init(overrides: [String: Bool] = [:]) {
        self.overrides = [:]
        for (id, distracting) in overrides { set(id, distracting: distracting) }
    }

    public static let `default` = DistractionCatalog()

    /// The key time is filed under: the site for a browser whose title names one, else the app.
    /// The title is read here and never kept.
    public static func key(appId: String, windowTitle: String? = nil) -> String {
        let id = appId.lowercased()
        if browsers.contains(id), let title = windowTitle?.lowercased(),
           let site = sites.first(where: { $0.titleMarkers.contains(where: title.contains) }) {
            return site.key
        }
        return id
    }

    public func isDistracting(_ key: String) -> Bool {
        let id = key.lowercased()
        if Self.lockedDistracting.contains(id) { return true }
        return overrides[id] ?? Self.shippedDistracting.contains(id)
    }

    /// Whether the person may mark `key` as fine (the locked feeds can't be).
    public func canChange(_ key: String) -> Bool { !Self.lockedDistracting.contains(key.lowercased()) }

    /// Marks `key` distracting or fine. Asking to mark a locked feed fine does nothing.
    public mutating func set(_ key: String, distracting: Bool) {
        let id = key.lowercased()
        guard canChange(id) else { return }
        overrides[id] = distracting == Self.shippedDistracting.contains(id) ? nil : distracting
    }

    /// Back to the shipped choice for `key`.
    public mutating func reset(_ key: String) { overrides[key.lowercased()] = nil }
}
