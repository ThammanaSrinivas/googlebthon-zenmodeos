import Foundation
import Testing
import ZenAPI
import ZenLogic
@testable import MacUsage

/// Drives a tracker through a script, ticking every 5 s like the adapter does.
struct Script {
    static let india = TimeZone(identifier: "Asia/Kolkata")!
    /// 2026-11-20 10:00 in India.
    static let start = Date(timeIntervalSince1970: 1_795_149_000)
    static let youtube = "web:youtube"
    static let vlc = "org.videolan.vlc"
    static let xcode = "com.apple.dt.xcode"
    static let netflixSite = "web:netflix"

    var tracker: UsageTracker
    var now: Date

    init(frontmost: String? = nil, at start: Date = Script.start, catalog: DistractionCatalog = .default) {
        tracker = UsageTracker(catalog: catalog, timeZone: Self.india, startingAt: start, frontmost: frontmost)
        now = start
    }

    /// Lets `seconds` pass with ticks.
    mutating func wait(_ seconds: TimeInterval) {
        let end = now + seconds
        while now < end {
            now = min(now + 5, end)
            tracker.handle(.tick(at: now))
        }
    }

    mutating func open(_ app: String) { tracker.handle(.appActivated(app, at: now)) }
    mutating func send(_ event: (Date) -> UsageEvent) { tracker.handle(event(now)) }

    var today: UsageDay { tracker.today(now: now) }
}

struct UsageTrackerTests {
    @Test func onlyDistractingTimeCounts() {
        var s = Script(frontmost: Script.xcode)
        s.wait(600)
        s.open(Script.youtube)
        s.wait(300)
        s.open(Script.xcode)
        s.wait(600)
        #expect(s.today.countedMinutes == 5)
        #expect(s.today.day == "2026-11-20")
        #expect(!s.tracker.isCounting)
    }

    @Test func theOpenSessionCountsUpToNow() {
        var s = Script(frontmost: Script.vlc)
        s.wait(125)
        #expect(s.tracker.isCounting)
        #expect(s.today.distractingMillis == 125_000)
        #expect(s.today.countedMinutes == 2)
    }

    @Test func bundleIdsAreMatchedWhateverTheirCase() {
        var s = Script(frontmost: "org.VideoLAN.VLC")
        s.wait(60)
        #expect(s.today.countedMinutes == 1)
        #expect(s.tracker.frontmostApp == Script.vlc)
    }

    @Test func idleStopsTheCountAndInputResumesIt() {
        var s = Script(frontmost: Script.youtube)
        s.wait(600)
        s.send { .idleStarted(at: $0) }
        s.wait(600)
        #expect(s.today.countedMinutes == 10)
        s.send { .idleEnded(at: $0) }
        s.wait(120)
        #expect(s.today.countedMinutes == 12)
    }

    @Test func sleepStopsAndWakeWaitsForFreshInput() {
        var s = Script(frontmost: Script.youtube)
        s.wait(300)
        s.send { .sleep(at: $0) }
        s.now += 3_600 // asleep: no ticks
        s.send { .wake(at: $0) }
        s.wait(120) // YouTube on screen, nobody touched anything
        #expect(s.today.countedMinutes == 5)
        s.send { .idleEnded(at: $0) }
        s.wait(60)
        #expect(s.today.countedMinutes == 6)
    }

    @Test func aGapInTheEventsIsASleep() {
        var s = Script(frontmost: Script.youtube)
        s.wait(120)
        s.now += 1_800 // the app was suspended: no ticks, no sleep notification
        s.wait(60)
        #expect(s.today.countedMinutes == 2)
        s.open(Script.youtube) // bringing it to the front is input
        s.wait(60)
        #expect(s.today.countedMinutes == 3)
    }

    @Test func aClockSetBackNeverRemovesTime() {
        var s = Script(frontmost: Script.youtube)
        s.wait(300)
        s.tracker.handle(.tick(at: s.now - 3_600))
        #expect(s.today.countedMinutes == 5)
    }

    @Test func comingBackWithinFiveMinutesIsAPullBack() {
        var s = Script(frontmost: Script.youtube)
        s.wait(120)
        s.open(Script.xcode)
        s.wait(60)
        s.open(Script.youtube) // back after a minute
        s.wait(60)
        #expect(s.today.pullBacks == 1)
        s.open(Script.xcode)
        s.wait(600)
        s.open(Script.youtube) // back after ten minutes: a fresh start, not a pull-back
        s.wait(60)
        #expect(s.today.pullBacks == 1)
    }

    @Test func movingBetweenFeedsIsNotLeaving() {
        var s = Script(frontmost: Script.youtube)
        s.wait(120)
        s.open(Script.netflixSite)
        s.wait(120)
        s.open(Script.vlc)
        s.wait(120)
        #expect(s.today.pullBacks == 0)
        #expect(s.today.countedMinutes == 6)
    }

    @Test func aShortGlanceAwayIsABlipUnlessAnotherAppWasUsed() {
        var s = Script(frontmost: Script.youtube)
        s.wait(120)
        s.send { .idleStarted(at: $0) }
        s.wait(10)
        s.send { .idleEnded(at: $0) } // 10 s away, no other app: a blip
        s.wait(60)
        #expect(s.today.pullBacks == 0)
        s.send { .idleStarted(at: $0) }
        s.wait(20)
        s.send { .idleEnded(at: $0) } // 20 s away: came back
        s.wait(60)
        #expect(s.today.pullBacks == 1)
    }

    @Test func aWindowGrabbingFocusIsNoStartingPoint() {
        var s = Script(frontmost: Script.xcode)
        s.wait(60)
        s.open(Script.youtube) // 10 s: a window opening, not a visit
        s.wait(10)
        s.open(Script.xcode)
        s.wait(60)
        s.open(Script.youtube)
        s.wait(60)
        #expect(s.today.pullBacks == 0)
    }

    @Test func aFlickerShorterThanATickIsIgnored() {
        var s = Script(frontmost: Script.youtube)
        s.wait(120)
        s.open(Script.xcode)
        s.now += 2
        s.open(Script.youtube) // alt-tab and straight back
        s.wait(60)
        #expect(s.today.pullBacks == 0)
    }

    @Test func midnightSplitsTheDayAndFinishesYesterday() {
        // 23:50 in India.
        let lateEvening = Script.start + 13 * 3_600 + 50 * 60
        var s = Script(frontmost: Script.youtube, at: lateEvening)
        s.wait(20 * 60)
        let finished = s.tracker.drainFinishedDays()
        #expect(finished == [UsageDay(day: "2026-11-20", distractingMillis: 600_000, pullBacks: 0)])
        #expect(s.today.day == "2026-11-21")
        #expect(s.today.countedMinutes == 10)
        #expect(s.tracker.drainFinishedDays().isEmpty)
    }

    @Test func changingTheCatalogReclassifiesToday() {
        var s = Script(frontmost: Script.xcode)
        s.wait(300)
        #expect(s.today.countedMinutes == 0)
        s.tracker.catalog.set(Script.xcode, distracting: true)
        #expect(s.today.countedMinutes == 5)
    }

    @Test func nothingInFrontCountsNothing() {
        var s = Script()
        s.wait(600)
        #expect(s.today == UsageDay(day: "2026-11-20", distractingMillis: 0, pullBacks: 0))
    }
}

struct IdleWatcherTests {
    let t0 = Script.start

    @Test func crossingTheThresholdStartsIdleAtTheMomentItCrossed() {
        var watcher = IdleWatcher(threshold: 1_800, pollInterval: 5)
        #expect(watcher.poll(now: t0, secondsSinceInput: 1_799).isEmpty)
        #expect(watcher.poll(now: t0 + 5, secondsSinceInput: 1_804) == [.idleStarted(at: t0 + 1)])
        #expect(watcher.poll(now: t0 + 10, secondsSinceInput: 1_809).isEmpty)
        #expect(watcher.poll(now: t0 + 15, secondsSinceInput: 2) == [.idleEnded(at: t0 + 13)])
        #expect(watcher.poll(now: t0 + 20, secondsSinceInput: 1).isEmpty)
    }

    @Test func afterAWakeOnlyNewInputEndsIdle() {
        var watcher = IdleWatcher(threshold: 1_800, pollInterval: 5)
        watcher.didWake(at: t0)
        // The OS still reports input from before the sleep.
        #expect(watcher.poll(now: t0 + 5, secondsSinceInput: 3_600).isEmpty)
        #expect(watcher.poll(now: t0 + 10, secondsSinceInput: 1) == [.idleEnded(at: t0 + 9)])
        #expect(watcher.poll(now: t0 + 15, secondsSinceInput: 1).isEmpty)
    }

    @Test func aWakeWithInputJustBeforeItCountsAsFresh() {
        var watcher = IdleWatcher(threshold: 1_800, pollInterval: 5)
        watcher.didWake(at: t0)
        // The key press that woke it lands a moment before the wake notification.
        #expect(watcher.poll(now: t0 + 1, secondsSinceInput: 3) == [.idleEnded(at: t0)])
    }
}

struct DistractionCatalogTests {
    @Test func theShippedListsFollowTheDesktopApp() {
        let catalog = DistractionCatalog.default
        #expect(catalog.isDistracting("web:youtube"))
        #expect(catalog.isDistracting("com.valvesoftware.steam"))
        #expect(catalog.isDistracting("ORG.VIDEOLAN.VLC"))
        #expect(!catalog.isDistracting("com.apple.dt.xcode"))
        #expect(!catalog.isDistracting("com.tinyspeck.slackmacgap")) // chat is neutral
        #expect(!catalog.isDistracting("com.apple.safari")) // a browser is decided by its site
    }

    @Test func peopleCanMoveAppsButNotTheLockedFeeds() {
        var catalog = DistractionCatalog()
        catalog.set("com.apple.music", distracting: true)
        #expect(catalog.isDistracting("com.apple.music"))
        catalog.set("com.valvesoftware.steam", distracting: false)
        #expect(!catalog.isDistracting("com.valvesoftware.steam"))
        catalog.set("web:youtube", distracting: false)
        #expect(catalog.isDistracting("web:youtube"))
        #expect(!catalog.canChange("web:instagram"))
        catalog.reset("com.valvesoftware.steam")
        #expect(catalog.isDistracting("com.valvesoftware.steam"))
        // Setting the shipped choice keeps no override.
        catalog.set("com.apple.music", distracting: false)
        #expect(catalog.overrides.isEmpty)
    }

    @Test func overridesSurviveCoding() throws {
        var catalog = DistractionCatalog()
        catalog.set("com.apple.music", distracting: true)
        let data = try JSONEncoder().encode(catalog)
        #expect(try JSONDecoder().decode(DistractionCatalog.self, from: data) == catalog)
    }

    @Test func aBrowserTitleNamesTheSite() {
        #expect(DistractionCatalog.key(appId: "com.google.Chrome", windowTitle: "Funny cats - YouTube") == "web:youtube")
        #expect(DistractionCatalog.key(appId: "com.apple.Safari", windowTitle: "Home / X") == "web:x")
        #expect(DistractionCatalog.key(appId: "com.apple.Safari", windowTitle: "Swift docs") == "com.apple.safari")
        #expect(DistractionCatalog.key(appId: "com.apple.dt.Xcode", windowTitle: "youtube.swift") == "com.apple.dt.xcode")
        #expect(DistractionCatalog.key(appId: "com.apple.Safari") == "com.apple.safari")
    }
}

struct ComputerDayReportBuilderTests {
    let day = UsageDay(day: "2026-11-20", distractingMillis: 42 * 60_000 + 59_000, pullBacks: 3)

    @Test func theDeviceIdIsRandomHexAndKept() {
        let store = InMemoryKeyValueStore()
        let builder = ComputerDayReportBuilder(store: store)
        let id = builder.deviceId
        #expect(ComputerDayReportBuilder.isDeviceId(id))
        #expect(ComputerDayReportBuilder(store: store).deviceId == id)
        #expect(ComputerDayReportBuilder(store: InMemoryKeyValueStore()).deviceId != id)
    }

    @Test func aBrokenStoredIdIsReplaced() {
        let store = InMemoryKeyValueStore([ComputerDayReportBuilder.Keys.deviceId: "not-an-id"])
        #expect(ComputerDayReportBuilder.isDeviceId(ComputerDayReportBuilder(store: store).deviceId))
    }

    @Test func theSequenceOnlyGrowsAcrossLaunches() {
        let store = InMemoryKeyValueStore()
        let first = ComputerDayReportBuilder(store: store).report(for: day)
        let second = ComputerDayReportBuilder(store: store).report(for: day)
        #expect(first.sequence == 1)
        #expect(second.sequence == 2)
    }

    @Test func theReportCarriesTheDay() {
        let builder = ComputerDayReportBuilder(store: InMemoryKeyValueStore())
        let report = builder.report(for: day)
        #expect(report.day == "2026-11-20")
        #expect(report.countedMinutes == 42)
        #expect(report.pullBacks == 3)
        #expect(report.promiseMinutes == 240)
        #expect(report.platform == .macos)
    }

    @Test func thePromiseIsWholeHoursOneToTwelve() {
        let builder = ComputerDayReportBuilder(store: InMemoryKeyValueStore())
        builder.promiseHours = 6
        #expect(builder.report(for: day).promiseMinutes == 360)
        builder.promiseHours = 40
        #expect(builder.promiseHours == 12)
        builder.promiseHours = 0
        #expect(builder.promiseHours == 1)
    }

    @Test func valuesAreKeptInsideTheContractsBounds() {
        let builder = ComputerDayReportBuilder(store: InMemoryKeyValueStore())
        let huge = builder.report(for: UsageDay(day: "2026-11-20", distractingMillis: 2_000 * 60_000, pullBacks: 5_000))
        #expect(huge.countedMinutes == 1_500)
        #expect(huge.pullBacks == 1_000)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "zen.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsKeyValueStore(defaults)
        store.set("x", forKey: "k")
        #expect(store.string(forKey: "k") == "x")
        store.set(nil, forKey: "k")
        #expect(store.string(forKey: "k") == nil)
    }

    @Test func theRandomIdUsesTheGenerator() {
        var generator = RepeatingGenerator()
        #expect(ComputerDayReportBuilder.randomDeviceId(using: &generator) == String(repeating: "f", count: 32))
    }
}

struct RepeatingGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { 15 }
}
