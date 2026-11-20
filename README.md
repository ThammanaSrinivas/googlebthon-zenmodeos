# ZenMode OS · Mac and iPhone

ZenMode OS helps people put the phone down without a blocker they'll uninstall: one Zen Score
across every screen, and Zeno, a small character who lives in the Mac notch and the iPhone
Dynamic Island and says one calm line when it matters. Built for Startup Buildathon India 2026
(Google × Hack2skill).

- **For campuses and teams (per seat):** a cohort joins with a six-character code. Admins see one
  group score and trend, only for groups of 5 or more: never a name, an app or a minute.
- **For each person:** the same score on the iPhone and the Mac, a weekly streak (4 good days win
  the week), Zen Gold for won weeks, and Zeno's lines written by Gemini from outcomes only.

## Run the Mac app

Needs macOS 26 and Xcode 26 or later (Swift 6.2).

```bash
scripts/build-mac-app.sh --open     # builds "ZenMode OS.app" and launches it
swift test                          # contracts, rules and Zeno
scripts/snapshot-tour.sh /tmp/zen   # debug: renders every screen to PNG
```

Without the private repo beside this one, the app runs on fakes and every surface that shows
their numbers is labelled **Demo data**.

## How it's built

```
Sources/
  ZenAPI/      contracts and pure rules: the score, the weekly streak, the Zeno nudge schema
               and its guardrails, join codes, the 5+ cohort rule, quiet hours. No UI, no network.
  ZenMock/     fakes behind the same contracts, for the open build, the tests and offline demos.
  Albeit/      the design system: tokens, type, Zeno (eight feelings, springs at 240 Hz),
               the lit backdrop, Liquid Glass components.
  ZenModeMac/  the app: the notch panel, onboarding, Today, macOS platform code.
Tests/         Swift Testing suites for ZenAPI and Albeit.
```

- **Open core.** The app only ever sees the protocols in `ZenAPI`. Firebase, sync and the Gemini
  callables live in a private package (`ZenPrivate`), which `Package.swift` links when that repo is
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
- **macOS.** App Nap is held off (activity + `NSAppSleepDisabled`), the front app is tracked from
  activation notifications rather than polling, and Accessibility is asked for once, with the reason.
- **Accessibility.** VoiceOver labels on every control and on Zeno's lines, keyboard paths through
  onboarding (Return, ←/→, ⌘←), Reduce Motion lands everything in place.

Bundle ids: `com.zenmodeos.buildathon.mac`, `com.zenmodeos.buildathon.ios`.

## Licence

GPLv3. Clash Display, Geist and Departure Mono load from the system when installed; the app
falls back to the system faces otherwise.
