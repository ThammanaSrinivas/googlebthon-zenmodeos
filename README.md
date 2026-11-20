<p align="center">
  <img src="Apps/Mac/Sources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="104" alt="The ZenMode OS app icon">
</p>

<h1 align="center">ZenMode OS for Teams</h1>

<p align="center">
  <b>Lock in. Log off.</b><br>
  One switch silences every tool. Zeno catches you up after.<br>
  Your evenings stay yours. Leaders see how focus is going, never who.
</p>

<p align="center">
  <img alt="Startup Buildathon India 2026" src="https://img.shields.io/badge/Startup_Buildathon_India-2026-2AA136?style=flat-square&labelColor=12160F">
  <img alt="Gemini Live API and Gemini Flash" src="https://img.shields.io/badge/Gemini-Live_API_%2B_Flash-8E75FF?style=flat-square&labelColor=12160F">
  <img alt="macOS 26 and iOS 26" src="https://img.shields.io/badge/macOS_26_%C2%B7_iOS_26-SwiftUI-F3F2EC?style=flat-square&labelColor=12160F">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&labelColor=12160F">
  <img alt="825 tests at the freeze" src="https://img.shields.io/badge/tests-825_at_the_freeze-2AA136?style=flat-square&labelColor=12160F">
  <img alt="GPLv3" src="https://img.shields.io/badge/licence-GPLv3-FFC800?style=flat-square&labelColor=12160F">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/site-hero-dark.jpg">
  <img src="docs/readme/site-hero.jpg" alt="The ZenMode OS for Teams landing page: Turn busy teams into focused teams, with a Focus mode switch in a cloud of notification badges">
</picture>

<p align="center">
  <img src="docs/readme/zeno-notch.gif" width="640" alt="Zeno in the Mac notch: Focusing until 12:00, I'll keep watch. Later: Work's done, wrap up, then log off.">
  <br>
  <sub>Zeno lives in the Mac notch. A screen recording of the Mac app: one calm line when a block starts, another when the workday ends.</sub>
</p>

ZenMode OS turns busy teams into focused teams. One Focus switch on the Mac turns on Do Not
Disturb, sets your Slack status and books the time in your calendar, all at once. When the block
ends, Zeno catches you up on what you missed, and when the workday ends it guards your evening.
Zeno is a small character who lives in the Mac notch and the iPhone Dynamic Island. It says one
calm line when it matters, and talks with you through Gemini Live when you ask.

Built for **Startup Buildathon India 2026** (Google × Hack2skill). Companies and campuses pay per
seat, and every seat is a person with the full app. The admin sees anonymous team numbers for
groups of 5 or more, plus a monthly report written by Gemini, and never a name next to a number.

<p align="center">
  <a href="#a-day-with-zenmode-os">A day with it</a> ·
  <a href="#the-site">The site</a> ·
  <a href="#whats-in-it">What's in it</a> ·
  <a href="#where-gemini-comes-in">Gemini</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#run-it">Run it</a> ·
  <a href="#how-its-built">How it's built</a> ·
  <a href="#focus-mode-and-its-hooks">Hooks</a> ·
  <a href="#open-core-and-the-private-package">Open core</a> ·
  <a href="#cross-device-sync">Sync</a> ·
  <a href="#zeno-voice">Zeno Voice</a> ·
  <a href="#tests">Tests</a>
</p>

## A day with ZenMode OS

Screens from the Mac app. Shots labelled **live** ran the signed app on the live backend, with
Gemini writing the plan, the catch-up and the report; the team behind them is a seeded demo team,
and Slack is a demo workspace. The rest run on the app's built-in fakes and say **Demo data** on
screen.

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/readme/app-focus.jpg" alt="Today with Focus until 12:00 and a chip for each hook: Do Not Disturb, Slack, Calendar, Webhook">
      <p><b>09:30 · Lock in.</b> One switch. Each hook shows a chip, and a hook that isn't set up says what it needs. Focus starts anyway.<br><sub>DEMO DATA</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/readme/app-plan.jpg" alt="Plan my day: five tasks become a top three and four focus blocks, written by Zeno with Gemini">
      <p><b>Plan my day.</b> Five tasks in, the top three and four focus blocks out, around your meetings. <i>Zeno · Gemini</i> only when Gemini wrote it.<br><sub>LIVE · GEMINI</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/readme/app-catch-up.jpg" alt="What did I miss: three things need you, each with a drafted reply, one already sent">
      <p><b>12:00 · What did I miss?</b> The Slack mentions and DMs from the block, as three cards with drafts. Nothing sends until you press Send.<br><sub>LIVE · GEMINI</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/readme/app-after-hours.jpg" alt="Focus Mode hooks and work hours: Slack connected, Offline back Monday 9:30 AM">
      <p><b>18:30 · Log off.</b> The four hooks and your work hours. When work ends, Slack says "Offline, back Monday 9:30 AM" and the Mac goes quiet.<br><sub>LIVE · DEMO SLACK WORKSPACE</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/readme/app-your-day.jpg" alt="Your day: Zen Score 8.1 across iPhone and Mac, a 9-week streak, Zeno's line, the day as a clock and where the minutes went">
      <p><b>Your day.</b> One Zen Score across your screens, the weekly streak, and where this Mac's minutes went. The iPhone sends its score only.<br><sub>DEMO DATA</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/readme/app-week.jpg" alt="Week: four good days win the week, Zeno's read of the week, and questions to ask about it">
      <p><b>Your week.</b> Four good days win the week. Zeno's read comes from your numbers, never from your apps.<br><sub>DEMO DATA</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/readme/app-cards.jpg" alt="Zen Circle, Zen Gold, Zen Cards in Tamil, and a fanned deck of pattern cards">
      <p><b>Circle, Gold and cards.</b> Your circle's score, Zen Gold for won weeks, Zen Cards in your own language, and the patterns Zeno noticed, dealt as cards.<br><sub>DEMO DATA</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/readme/app-handoff.jpg" alt="Onboarding hand-off: the same Zen Score of 8.1 on an iPhone and a Mac, with a team join code">
      <p><b>Same score, two screens.</b> Onboarding ends on the hand-off: the iPhone and the Mac show one number, and a six-character code joins your team.<br><sub>DEMO DATA</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/readme/app-admin.jpg" alt="Team admin: rupees reclaimed a month, focus hours per person by week, and four metrics week on week">
      <p><b>For leaders.</b> What the team's focus is worth, how the formula counts it, and four metrics week on week. Team numbers only, for 5 or more.<br><sub>LIVE · SEEDED DEMO TEAM</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/readme/app-admin-report.jpg" alt="The monthly people report written by Gemini from team averages, with two suggestions">
      <p><b>The monthly people report.</b> Written by Gemini from team averages, with two things to try. Never a name next to a number.<br><sub>LIVE · GEMINI · SEEDED DEMO TEAM</sub></p>
    </td>
  </tr>
</table>

## The site

The landing page for the pitch, live on Firebase Hosting.

<table>
  <tr>
    <td width="50%"><img src="docs/readme/site-problem.jpg" alt="The problem: interrupted every 2 minutes, 59% burnout symptoms, $14B a year"></td>
    <td width="50%"><img src="docs/readme/site-app.jpg" alt="The app tour: your whole day on one calm screen, inside a Mac"></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/readme/site-people.jpg" alt="For your people: the work app that wants you to log off"></td>
    <td width="50%"><img src="docs/readme/site-leaders.jpg" alt="For leaders: the big picture, only the big picture"></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/readme/site-trust.jpg" alt="Trust: Bossware? Never heard of her. The deal, in writing"></td>
    <td width="50%"><img src="docs/readme/site-how.jpg" alt="How it works in three steps, and Powered by Gemini: Zeno sees outcomes, never your apps"></td>
  </tr>
</table>

<p align="center">
  <img src="docs/readme/zeno-moods.jpg" alt="Zeno in five of its feelings: happy, pleasant, curious, calm and proud">
  <br>
  <sub>Zeno is drawn in code by Albeit, the design system in this repo: eight feelings, springs at 240 Hz.</sub>
</p>

## What's in it

**For each person**

| Feature | What it does |
|---|---|
| **Focus Mode** | One switch: 25, 50 or 90 minutes, or until a set time. Do Not Disturb comes on (through two Shortcuts), Slack says "Focusing until 12:00" and snoozes, a busy event lands in your calendar, and a signed webhook tells anything else you use. Each hook shows a chip (on, failed or skipped), and a hook that fails never stops focus. |
| **Catch-up** | When a block ends, the Mac reads the Slack mentions and DMs that came in since it started. Tap *Catch me up* and Gemini returns up to three cards, each with a draft reply. Nothing is sent until you press Send, or Schedule after hours. |
| **Plan my day, Wrap up** | Type the day's tasks once. *Plan my day* reads your busy calendar and returns your top three and focus blocks to book. *Wrap up* turns what's done and what's open into a summary and a list for tomorrow. |
| **After-hours guard** | When your work hours end: a wrap-up nudge, Slack "Offline, back 9:30 AM", a Slack snooze and Do Not Disturb. A focus block that ends in the evening puts all of it back. Night shifts that cross midnight work too. |
| **Focus follows you** | The iPhone shows the Mac's focus in the app, on the Lock Screen and in the Dynamic Island (a Live Activity). |
| **Talk to Zeno** | Press ⌃⌥Z in any app, or say "Hey Zeno" (off until you turn it on). Zeno answers in Tamil, Hindi, Tanglish, Hinglish or English, and can start a focus block, set an intent timer or read you your Zen Score. |
| **Ask Zeno about the team** | Zeno answers only from the notes your admin wrote, and shows the quote. If the answer isn't there, it says "I don't have that in the team's notes." |
| **Today, Week, Calendar** | One Zen Score across your screens, the weekly streak (4 good days win the week), Zen Circle and Zen Gold. The week's recaps play as stories, and ⌘K reaches everything (typing "Zeno, focus 25 min" works there too). |

**For the team**

| Feature | What it does |
|---|---|
| **Join** | A six-character code or a link. A "What my admin sees" page shows exactly that. |
| **Team admin** | In the Mac sidebar (for the admin only) and on the web. What the team's focus hours are worth in rupees, four metrics week on week, focus hours by week, Zen Gold weeks and the monthly people report, with Regenerate. Under 5 people: one line, no numbers. |
| **My Focus Report** | A share link for your own week. Your name appears only if you tick it. |
| **Zen Gold for teams** | When the company sponsors it, you claim it after 5 days with a kept focus block in a week. |

## Where Gemini comes in

| What | Model | How |
|---|---|---|
| Talk to Zeno (Zeno Voice) | **Gemini Live API**, native audio in and out | The app gets a single-use, locked token from the backend, so the API key never reaches a device. Zeno's 7 tools turn what you said into actions on the device. |
| Catch-up, Plan my day, Wrap up, Ask Zeno | **Gemini Flash on Vertex AI**, called by the backend | A response schema, then a validator: lengths, no app names, no unkind or medical words, no links, no invented commitments in drafts, and Ask Zeno's quote must really be in the notes. Any failure or timeout returns a fixed fallback. |
| The monthly people report | **Gemini**, on the backend | Written from the team's anonymous numbers, only for groups of 5 or more. |

The app labels a line "Zeno · Gemini" only when Gemini wrote it, and plain "Zeno" when it's the
fallback. Zeno's everyday nudges in the notch are written by rules, not by Gemini. The "Hey Zeno"
wake word is Apple's on-device speech recognition.

## Privacy

- **Only the Zen Score leaves an iPhone.** Screen Time minutes, apps and sessions stay on the phone.
- **The Mac reads window titles and keeps none.** It reads the front window's title to tell
  YouTube from Docs, classifies it, and drops it.
- **Team numbers exist only for groups of 5 or more.** This is enforced in the type
  (`CohortSummary`) and on the server. An admin never sees a name next to a number.
- **Catch-up stays on the Mac until you ask.** Slack messages go to Gemini only when you tap
  *Catch me up*. The Slack token lives in the Keychain.
- **The webhook carries no account id, email or app name**, and is signed with HMAC-SHA256.
- **"Hey Zeno" runs on the Mac and keeps nothing.** The mic is released while Zeno talks.
  With Zeno Voice, intents, focus sessions and app pauses run on the device (`OnDeviceLedger`),
  and app names never go to the backend.
- **Zeno stays quiet** in the class or work hours chosen at onboarding, and every night from
  22:30 to 07:00.

## Run it

Needs macOS 26 and Xcode 26 or later (Swift 6.2).

**Signed apps (Sign in with Apple, Google sign-in):** open `Apps/ZenModeOS.xcodeproj` and run
the `ZenModeOSMac` or `ZenModeOSiPhone` scheme. Two files per app stay out of this repo:

| File | What goes in it |
|---|---|
| `Apps/<Mac or iPhone>/Sources/GoogleService-Info.plist` | That app's Firebase config |
| `Apps/Config/<Mac or iPhone>.local.xcconfig` | `GOOGLE_REVERSED_CLIENT_ID = <REVERSED_CLIENT_ID from that plist>` |

The second file becomes the app's URL scheme, which is how Google sign-in hands the person back.
Run the signed Mac app from Xcode only: every extra build registers another copy of the app, and
any copy can claim Google's return link. If sign-in comes back to the wrong copy, unregister the
strays with `lsregister -u`.

**Quick local runs and tests (no signing):**

```bash
scripts/build-mac-app.sh --open     # unsigned "ZenMode OS.app" (debug), launched
swift test                          # the Mac app, the iPhone app and Albeit, on a Mac
scripts/test-linux.sh               # Packages/ZenShared: contracts, rules, sync, focus, voice (also on Linux)
scripts/snapshot-tour.sh /tmp/zen   # debug: renders onboarding and Today to PNG
```

Without the private repo beside this one, the app runs on fakes, and every surface that shows
their numbers is labelled **Demo data**.

**Try Focus Mode end to end (debug build).** A local receiver checks each webhook's signature:

```bash
node scripts/webhook-receiver.mjs "$SECRET" &      # prints VERIFIED or BAD SIGNATURE per event
ZEN_WEBHOOK_URL=http://127.0.0.1:8787/hook ZEN_WEBHOOK_SECRET="$SECRET" \
ZEN_FOCUS_MINUTES=2 ZEN_FOCUS_END_AFTER=12 "build/ZenMode OS.app/Contents/MacOS/ZenModeMac"
```

The app starts a 2-minute block 2 seconds after launch and ends it early 12 seconds later. You'll
see `focus_start` and then `focus_end` with `kept: false`, and stderr prints a `[focus]` line for
each hook's state and a `[sync]` line for each write. To see the iPhone's Live Activity without a
Mac, run the iPhone app with `ZEN_DEMO_FOCUS=1`.

## How it's built

```
Package.swift      the apps' libraries: Albeit, ZenMacApp, ZenPhoneApp, on Packages/ZenShared (+ ZenCorePrivate when present)
Sources/
  Albeit/        the design system: tokens, type, contrast checks, buttons with every state, the lit
                 backdrop, Liquid Glass components, and Zeno (eight feelings, springs at 240 Hz).
  ZenMacApp/     the Mac app as a library:
    Notch/         the notch panel, Zeno's cues and Talk to Zeno (⌃⌥Z, "Hey Zeno")
    Onboarding/    two ways in (team member or team admin), quiet hours, the hand-off
    Today/         five sections, Focus as the one primary, Get set up, ⌘K
    Focus/         Focus Mode on the Mac: the calendar hook (EventKit), catch-up, plan and wrap-up,
                   the after-hours guard, the Keychain, the team card
    Admin/         Team admin: the rupee band, the metrics, the people report
    Week/ Calendar/ Circle/ Gold/ Integrations/ Settings/
  ZenModeMac/    `swift run` host for ZenMacApp.
  ZenPhoneApp/   the iPhone app as a library: sign-in, the live score, the Mac's focus, approving a Mac.
Apps/            the Xcode project: the signed Mac and iPhone apps, the iPhone widgets and the focus
                 Live Activity, entitlements, Info.plists.
Tests/           AlbeitTests, ZenMacAppTests, ZenPhoneAppTests
Packages/ZenShared/  the shared, UI-free package (macOS, iOS and Linux)
  Sources/
    ZenAPI/        the one app contract: protocols and value types, plus the pure rules every
                   surface shares (the score, the weekly streak, the nudge schema and its
                   guardrails, join codes, the 5+ cohort rule, quiet hours, the sign-in nonce,
                   cross-device sync, the Teams types: focus blocks, work hours, the Zeno work calls).
    ZenLogic/      rules identical to the server's: the Zen Score formula (ZenScoreRule), local
                   days, the cross-device combine (CombineRule), the name policy, and
                   ScoreSnapshotBuilder (the snapshot every device shows).
    ZenFocus/      Focus Mode, pure and tested on Linux: the hook runner, the focus engine, Slack
                   (status, snooze, inbox), the signed webhook, Do Not Disturb through Shortcuts,
                   work windows, and "Zeno, focus N min".
    ZenMock/       fakes behind the same contracts, for the open build, the tests and offline
                   demos. FakeSync runs the real combine on every publish.
    MacUsage/      the Mac's distracting-minutes tracker, the report builder and MacDaySync (the
                   throttled publisher); the AppKit adapter sits behind `canImport(AppKit)`.
    ZenVoice/      Zeno Voice on the Gemini Live API: the wire protocol, Zeno's instruction and
                   tools, the on-device ledger, the session, the PCM maths, the offline replay and
                   VoiceModel (what the notch binds to).
  Tests/           Swift Testing suites, with the shared vectors in ZenLogicTests/Vectors.
```

- **Open core.** The app only ever sees the protocols in `ZenAPI`. Firebase, sync and the Gemini
  calls live in a private package (`ZenCorePrivate`), which `Package.swift` links when that repo
  is cloned beside this one; `ZEN_USE_MOCK=1` forces the fakes.
- **Signing.** Team CBH6YW2NR9. Mac: Sign in with Apple, Keychain Sharing, the microphone,
  calendars, hardened runtime, no App Sandbox (the sandbox blocks the Accessibility API the
  tracker uses to tell YouTube from Docs). iPhone: Sign in with Apple, Push, Family Controls, and
  Live Activities in its Info.plist.
- **macOS.** App Nap is held off (activity + `NSAppSleepDisabled`), the front app is tracked from
  activation notifications rather than polling, and Accessibility is asked for once, with the
  reason. ⌃⌥Z is a Carbon hot key, so it needs no permission and sees no other key.
- **Accessibility.** VoiceOver labels on every control and on Zeno's lines, keyboard paths through
  onboarding (Return, ←/→, ⌘←), hover, pressed and focus states on every Albeit button, every
  text colour at 4.5:1 or better on cards, ground and glass in light and dark (tested), and Reduce
  Motion lands everything in place.

Bundle ids: `com.zenmodeos.buildathon.mac`, `com.zenmodeos.buildathon.ios`.

## Focus Mode and its hooks

Every integration is a hook with the same shape: `id`, `displayName`, `status()` (ready, needs
setup or off), `onFocusStart` and `onFocusEnd`.

- **The runner** (`ZenFocus.HookRunner`) fires every ready hook at once, with a 5-second deadline
  each that holds even when a hook ignores cancellation. A failed hook is marked `failed` and the
  rest still run; a hook that isn't set up is `skipped` and never called.
- **End always runs**, for every hook that started, even after an early stop. The engine saves the
  block before any hook runs, so after a crash the next launch ends every ready hook.
- **The engine** writes the person's live focus, the session and the day. It gives up on a write
  after 4 seconds (so focus still ends offline), and keeps a signed-out Mac's sessions in an outbox
  until someone signs in.
- **Slack's status carries its own expiry**, so a crash still clears it.

The four hooks today:

| Hook | How |
|---|---|
| Do Not Disturb | Two Shortcuts ("ZenMode Focus On" and "ZenMode Focus Off"); Integrations › Focus Mode checks they exist |
| Slack | Status, emoji and expiry, plus a snooze, with the person's user token (kept in the Keychain) |
| Calendar | A busy event through macOS Calendar (EventKit), in the calendar you pick |
| Webhook | `POST {event, session_id, start_at, until, kept?, source}`, with `X-ZenMode-Signature: sha256=<HMAC-SHA256 of the raw body with your secret>`. Only https (or this Mac) |

`event` is `focus_start` or `focus_end`, and `kept` is sent only on the end.

## Open core and the private package

Everything in this repo is public (GPLv3) and builds with no backend at all. The live backend is
a separate, private Swift package, `ZenCorePrivate`, that implements the ZenAPI protocols:
`AuthService`, `DaySyncService`, `ScoreService`, `CohortService`, `ZenoNudgeService`,
`VoiceTokenService`, `ZenCardService`, `FocusSyncService`, `ZenoWorkService`, `TeamService` and
`AdminService`.

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
  still drawn from demo data (day history, the weekly review, circle patterns) say **Demo data** on
  either backend. In the Integrations catalog, every tool but the calendar is a **Demo connection**;
  Focus Mode's four hooks are real.
- Nothing here imports a backend SDK or names the backend's storage, and the guardrails below
  enforce that on every commit. `Apps/README.md` has the wiring notes.

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
- **The weekly streak** is computed on the device: a good day is a Zen Score above 6.0, 4 good days
  win the week (Monday to Sunday, India time), and a day with no data is neither good nor a zero.

## Zeno Voice

Say why you picked up the phone, in your own language, and Zeno acts on it. Zeno Voice is a
real-time voice agent on the **Gemini Live API** (native audio in and out). It understands Tamil,
Hindi, Tanglish, Hinglish and English, answers in the same mix, and turns what you said into a
ZenMode OS action: an intent timer in the island, a focus session, a pause in front of an app,
your Zen Score read aloud, or an evening note made into a Zen Card for your circle. It lives in
`Packages/ZenShared/Sources/ZenVoice` and runs its tests on Linux.

On the Mac, ⌃⌥Z or "Hey Zeno" opens a session from any app. Zeno finishes speaking before it
listens, and every chat comes down from the notch. "Zeno, focus 25 minutes" becomes a Focus Mode
block, with every hook.

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

`VoiceModel.demo(scores: FakeScores(), cards: FakeZenCards())` plays five moments with no mic, no
network and no key: scripted words, real tool calls on a ledger of its own.

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

`get_zen_status` reads the account's live, combined Zen Score through `ScoreService`. Only the
evening note goes to the backend, through `ZenCardService`: a Zen Card carries the summary, a mood
and the language, and the shared card adds the person's name, never a score next to a name.

## Tests

Counted at the code freeze (21 Nov 2026, 04:00 IST), every suite passing:

| Suite | Command | Tests |
|---|---|---|
| ZenShared (ZenAPI, ZenLogic, ZenMock, ZenFocus, ZenVoice, MacUsage) | `scripts/test-linux.sh` | 477 |
| The Mac app (ZenMacAppTests) | `swift test` | 263 |
| The iPhone app (ZenPhoneAppTests) | `swift test` | 32 |
| Albeit (the design system) | `swift test` | 53 |

- **What they pin down:** the hook runner's deadline and its end-after-crash; kept versus early
  stop; the weekly streak at the edges (6.0 isn't a good day; Sunday 23:59 and Monday 00:00 IST
  fall in different weeks); night shifts across midnight; Slack's request builders; the webhook
  body byte for byte and its HMAC against RFC 4231's test cases; the 5+ team rule; the wake word
  ("Zeno" counts, "ZenMode" never does); contrast for every text colour.
- **Mutation check:** each of these was broken on purpose, a test failed, and the change was
  reverted: a good day at ≥ 6.0, a timed-out hook counted as on, a night shift read as one day,
  the HMAC's inner pad, and an early stop counted as kept.
- **CI** (`.github/workflows/ci.yml`, on pushes to `main` and on pull requests): the shared
  package on Linux in `swift:6.4.1-noble`, the Mac app and the shared package on macOS with the
  fakes linked, and the guardrails.

**Not in this build:** a Microsoft Teams hook and mail in catch-up. The calendar hook goes through
macOS Calendar, so a Google account added there gets a busy event, not a Workspace "Focus time"
event. The iPhone's Live Activity starts only while the iPhone app is open (push-to-start isn't
built). QR pairing between the iPhone and the Mac is in the code, but off in the demo build
(`AppModel.qrPairingEnabled`).

## Contributing

- Work on `main`; force pushes and history rewrites are blocked.
- Guardrails (`.guardrails/`) run in the pre-commit hook, in Claude Code's hooks and in CI: no
  backend SDK imports, no backend storage or function names, no project ids, no signing files or
  app plists. Turn the hook on once per clone with `git config core.hooksPath .githooks` (it needs
  Python 3.11 or later); `.guardrails/gr list` shows the rules and `.guardrails/gr check --changed`
  checks your work.
- New shared logic goes in `Packages/ZenShared` with its tests, so it runs on Linux CI.

## Licence

GPLv3. Clash Display, Geist and Departure Mono load from the system when installed; the app
falls back to the system faces otherwise.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/site-cta-dark.jpg">
  <img src="docs/readme/site-cta.jpg" alt="Lock in. Log off. Zeno over hills at 6:30 PM, when work's gone quiet">
</picture>

<p align="center"><sub>Made with Gemini at Startup Buildathon India 2026 (Google × Hack2skill).</sub></p>
