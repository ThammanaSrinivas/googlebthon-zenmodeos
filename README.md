# ZenMode OS · Mac and iPhone

ZenMode OS helps people put the phone down without a blocker they'll uninstall: one Zen Score
across every screen, and Zeno, a small character who lives in the Mac notch and the iPhone
Dynamic Island and says one calm line when it matters. Built for Startup Buildathon India 2026
(Google × Hack2skill).

- **For campuses and teams (per seat):** a cohort joins with a six-character code. Admins see one
  group score and trend, only for groups of 5 or more: never a name, an app or a minute.
- **For each person:** the same score on the iPhone and the Mac, a weekly streak (4 good days win
  the week), Zen Gold for won weeks, and Zeno's lines written by Gemini from outcomes only.

## Run it

Needs macOS 26 and Xcode 26 or later (Swift 6.2).

**Signed apps (Sign in with Apple, Google sign-in):** open `Apps/ZenModeOS.xcodeproj` and run
the `ZenModeOSMac` or `ZenModeOSiPhone` scheme. Two files per app stay out of this repo:

| File | What goes in it |
|---|---|
| `Apps/<Mac or iPhone>/Sources/GoogleService-Info.plist` | That app's Firebase config |
| `Apps/Config/<Mac or iPhone>.local.xcconfig` | `GOOGLE_REVERSED_CLIENT_ID = <REVERSED_CLIENT_ID from that plist>` |

The second one becomes the app's URL scheme, which is how Google sign-in hands the person back.

**Quick local runs and tests (no signing):**

```bash
scripts/build-mac-app.sh --open     # unsigned "ZenMode OS.app", launched
swift test                          # Albeit (the design system), on a Mac
scripts/test-linux.sh               # Packages/ZenShared: contracts, rules, sync, fakes (also on Linux)
scripts/snapshot-tour.sh /tmp/zen   # debug: renders every screen to PNG
```

Without the private repo beside this one, the app runs on fakes and every surface that shows
their numbers is labelled **Demo data**.

## How it's built

```
Package.swift      the apps' libraries: Albeit, ZenMacApp, ZenPhoneApp, on Packages/ZenShared (+ ZenCorePrivate when present)
Sources/
  Albeit/        the design system: tokens, type, Zeno (eight feelings, springs at 240 Hz),
                 the lit backdrop, Liquid Glass components.
  ZenMacApp/     the Mac app as a library: the notch panel, onboarding, Today, macOS platform code.
  ZenModeMac/    `swift run` host for ZenMacApp.
  ZenPhoneApp/   the iPhone app as a library: sign-in, the live score, approving a Mac.
Apps/            the Xcode project: the signed Mac and iPhone app targets, entitlements, Info.plists.
Tests/AlbeitTests/
Packages/ZenShared/  the shared, UI-free package (macOS, iOS and Linux)
  Sources/
    ZenAPI/        the one app contract: protocols and value types, plus the pure rules every
                   surface shares (the score, the weekly streak, the Zeno nudge schema and its
                   guardrails, join codes, the 5+ cohort rule, quiet hours, sign-in nonce,
                   cross-device sync).
    ZenLogic/      rules identical to the server's: the Zen Score formula (ZenScoreRule), local
                   days, the cross-device combine (CombineRule), the name policy, and
                   ScoreSnapshotBuilder (the snapshot every device shows).
    ZenMock/       fakes behind the same contracts, for the open build, the tests and offline
                   demos. FakeSync runs the real combine on every publish.
    MacUsage/      the Mac's distracting-minutes tracker, the report builder and MacDaySync (the
                   throttled publisher); the AppKit adapter sits behind `canImport(AppKit)`.
    ZenVoice/      Zeno Voice on the Gemini Live API: the wire protocol, Zeno's instruction and
                   tools, the on-device ledger, the toolbox, the session, the PCM maths, the
                   offline replay and VoiceModel (what the notch binds to). The URLSession
                   transport and the AVAudioEngine adapter sit behind `canImport`.
  Tests/           Swift Testing suites, with the shared vectors in ZenLogicTests/Vectors.
```

- **Open core.** The app only ever sees the protocols in `ZenAPI`. Firebase, sync and the Gemini
  callables live in a private package (`ZenCorePrivate`), which `Package.swift` links when that repo is
  cloned beside this one; `ZEN_USE_MOCK=1` forces the fakes.
- **Rules decide when Zeno speaks; Gemini decides what it says.** The server calls Gemini Flash with
  a response schema (`feeling`, a line of at most 40 characters, one `action`). The app validates
  again, then `ResilientNudges` falls back to a fixed line on any error, timeout or broken
  guardrail, and says honestly which one you're seeing.
- **Privacy.** Only the Zen Score leaves an iPhone. The Mac reads the front window's title to tell
  YouTube from Docs, classifies it, and drops it: titles are read, never stored. Cohort numbers
  exist only for groups of 5 or more, enforced in the type (`CohortSummary`) and on the server.
- **The notch.** A click-through panel sits exactly on the camera housing; when Zeno speaks the
  black shape grows out of it, Zeno drops in, and the words arrive one by one. Zeno stays quiet in
  the class or work hours chosen at onboarding and every night from 22:30 to 07:00.
- **Signing.** Team CBH6YW2NR9. Mac: Sign in with Apple, Keychain Sharing, hardened runtime, no
  App Sandbox (the sandbox blocks the Accessibility API the tracker uses to tell YouTube from
  Docs). iPhone: Sign in with Apple, Push, Family Controls.
- **macOS.** App Nap is held off (activity + `NSAppSleepDisabled`), the front app is tracked from
  activation notifications rather than polling, and Accessibility is asked for once, with the reason.
- **Accessibility.** VoiceOver labels on every control and on Zeno's lines, keyboard paths through
  onboarding (Return, ←/→, ⌘←), Reduce Motion lands everything in place.

Bundle ids: `com.zenmodeos.buildathon.mac`, `com.zenmodeos.buildathon.ios`.

## Open core and the private package

Everything in this repo is public (GPLv3) and builds with no backend at all. The live backend is
a separate, private Swift package, `ZenCorePrivate`, that implements the ZenAPI protocols
(`AuthService`, `DaySyncService`, `ScoreService`, `CohortService`, `ZenoNudgeService`).

```
ZenMacApp ──▶ Packages/ZenShared ◀── ZenCorePrivate (private repo, optional)
     └────────────────────────────────────▲
```

- `ZenCorePrivate` depends only on `Packages/ZenShared` (ZenAPI for the contract, ZenLogic for the same
  combine the server runs), never on the root package, so there is no cycle.
- The root `Package.swift` links `ZenCorePrivate` when the private repo is cloned beside this one, at
  `../googlebthon-zenmodeos-private` (its root `Package.swift`), into ZenMacApp and ZenPhoneApp. Nothing
  under `Sources/` imports it: each app target picks the backend in its one wiring file
  (`Apps/Mac/Sources/ZenModeOSMacApp.swift`, `Apps/iPhone/Sources/ZenModeOSiPhoneApp.swift`) with
  `#if canImport(ZenCorePrivate)`, and falls back to the ZenMock fakes otherwise (`ZenMacBackend` /
  `ZenPhoneBackend`). `ZEN_USE_MOCK=1` forces the fakes; on Linux the root always uses them. Surfaces
  still drawn from demo data (day history, the weekly review, circle patterns, integrations) say
  **Demo data** on either backend.
- Nothing here imports a backend SDK or names the backend's storage, and the guardrails below
  enforce that on every commit.

## Cross-device sync

One Zen Score per person per day, the same number on every device and in their cohort seat,
within seconds of any device publishing.

- **The rule (founders, 20 Nov 2026): the lowest score wins.** The day's score is the lower of the
  phone's own score and the score of the computers' summed distracting minutes (their pull-backs
  add up, the largest promise counts). `ZenLogic.CombineRule` is the rule; the server runs its own
  port, and both replay `Packages/ZenShared/Tests/ZenLogicTests/Vectors/combine_v1.json`, a file
  the backend generates and this repo keeps byte-identical.
- **Freshness and places.** A phone that published within 18 hours decides the day; a computer
  holds its place for 7 days; the free plan counts the phone and one computer.
- **Privacy: an iPhone sends its score only.** `PhoneDayReport` drops minutes from an iPhone in
  its initialiser, so Screen Time minutes never leave the phone (DPLA 3.3.3(P)). Once an iPhone
  counts, the combined day carries no minutes either; device rows say "Counted on the phone".
- **The Mac** tracks distracting minutes and pull-backs (`MacUsage.UsageTracker`), builds a report
  with a random per-install id and a sequence that only grows, and `MacDaySync` publishes it: when
  it changes, at most every 30 seconds, at once on foreground, sign-in and midnight, with backoff
  while offline.

## Zeno Voice

Say why you picked up the phone, in your own language, and Zeno acts on it: Zeno Voice is a
real-time voice agent on the **Gemini Live API** (native audio in and out). It understands Tamil,
Hindi, Tanglish, Hinglish and English, answers in the same mix, and turns what you said into a
ZenMode OS action: an intent timer in the island, a focus session, a pause in front of an app, your
Zen Score read aloud, or an evening note made into a Zen Card for your circle. It lives in
`Packages/ZenShared/Sources/ZenVoice` and runs its tests on Linux.

**How the app uses it.** The notch and the island bind to `VoiceModel` (`@Observable`, no SwiftUI):

```swift
let voice = VoiceModel(tokens: services.voiceTokens, scores: services.scores, cards: services.cards,
                       ledger: OnDeviceLedger(store: UserDefaultsKeyValueStore()),
                       userName: user.firstName, audio: AVAudioVoiceIO())
await voice.start(pickup: true)   // on a pickup or a notch tap: Zeno asks "What are you here for?"
// voice.state            idle · connecting · listening · thinking · speaking · ended · error
// voice.lines            transcripts, each with its languageLabel ("Tanglish", "Hindi" …)
// voice.card             the tool card: intent timer, focus, pause, status, Zen Card
// voice.activeIntent     the island timer;  voice.timeUp when its minutes run out
// voice.latencyMs        end of speech to Zeno's first audio
await voice.stop()
```

`VoiceModel.demo(scores: FakeScores(), cards: FakeZenCards())` plays the five moments from the
prototype with no mic, no network and no key: scripted words, real tool calls on a ledger of its
own. `onDemoLine` hands each line (with its language and clip name) to the app to voice.

**Token flow.** The Gemini key never reaches a device.

```
app ──liveToken()──▶ backend (VoiceTokenService) ──▶ Gemini auth_tokens: single use,
 │                     connect within ~1 min, session ends after ~30 min, model + Zeno's
 │                     instruction + tools locked in
 └──wss …BidiGenerateContentConstrained?access_token=…──▶ Gemini Live
       setup (must match the token) → mic 16 kHz PCM16, 40 ms chunks → 24 kHz audio,
       transcripts, tool calls → tool responses
```

`ZenoSession` swaps a token past its `connectBy` for a fresh one, and on `goAway` or a dropped
connection resumes on a new token with the server's session resumption handle. Barge-in is the
server's (`START_OF_ACTIVITY_INTERRUPTS`); on `interrupted` the app flushes playback.

**Privacy.** Intents, focus sessions, app pauses and pickups run on the device in
`OnDeviceLedger`; app names never go to the backend. `get_zen_status` reads the account's live,
combined Zen Score through `ScoreService`, and Screen Time minutes are never sent anywhere. Only
the evening note goes to the backend, through `ZenCardService`: a Zen Card carries the summary,
a mood and the language, and the shared card adds the display name, never a score next to a name.

## Building and testing

- **Mac app:** macOS 26 with Xcode 26 (Swift 6.2): `scripts/build-mac-app.sh --open`, and
  `swift test` for Albeit.
- **Shared package:** `scripts/test-linux.sh` (or `cd Packages/ZenShared && swift test`) on macOS
  or Linux. With a toolchain unpacked at `~/.local/share/swift/6.4.1`, the script finds it.
- **CI** (`.github/workflows/ci.yml`, on pushes to `main` and on pull requests) runs the shared
  package's tests on Linux in `swift:6.4.1-noble`, and the guardrails.

## Contributing

- Work on `main`; force pushes and history rewrites are blocked.
- Guardrails (`.guardrails/`) run in the pre-commit hook, in Claude Code's hooks and in CI: no
  backend SDK imports, no backend storage or function names, no project ids, no signing files or
  app plists. Turn the hook on once per clone with `git config core.hooksPath .githooks`;
  `.guardrails/gr list` shows the rules and `.guardrails/gr check --changed` checks your work.
- New shared logic goes in `Packages/ZenShared` with its tests, so it runs on Linux CI.

## Licence

GPLv3. Clash Display, Geist and Departure Mono load from the system when installed; the app
falls back to the system faces otherwise.
