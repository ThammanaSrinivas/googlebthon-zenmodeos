# Apps: wiring notes

The Xcode project here hosts the signed Mac and iPhone apps. Each app picks its backend in one
wiring file (`Mac/Sources/ZenModeOSMacApp.swift`, `iPhone/Sources/ZenModeOSiPhoneApp.swift`):

```swift
#if canImport(ZenCorePrivate)
    import ZenCorePrivate
#endif
…
#if canImport(ZenCorePrivate)
if ProcessInfo.processInfo.environment["ZEN_USE_MOCK"] == nil, ZenCorePrivate.hasFirebaseConfig {
    let live = ZenCorePrivate.services()
    return PhoneServices(auth: live.auth, scores: live.scores, days: live.days, isDemo: false)
}
#endif
return .fakes()   // ZenServices.mock(): the ZenMock fakes
```

Nothing under `Sources/` or `Packages/` imports the private package; the guardrails enforce it.

## Zeno Voice (for Kamal)

The voice agent is the `ZenVoice` product of `Packages/ZenShared`. What the apps need to do:

1. **Link it.** Add `ZenVoice` to the app libraries' dependencies (`shared("ZenVoice")` for
   `ZenMacApp` and `ZenPhoneApp` in the root `Package.swift`) and to the Xcode targets'
   package products next to `ZenAPI` and `ZenMock`.
2. **Two more services.** Carry a `VoiceTokenService` and a `ZenCardService` next to `scores`
   in `PhoneServices` / `MacServices`: `FakeVoiceTokens()` and `FakeZenCards()` in `.fakes()`,
   the private package's in the live branch above.
3. **One ledger per app**, kept for the app's life:
   `OnDeviceLedger(store: UserDefaultsKeyValueStore())`. Run `await ledger.runTimers()` in a task
   while the island shows a timer, so `VoiceModel.timeUp` fires when an intent's minutes run out.
4. **The model.** `VoiceModel(tokens:scores:cards:ledger:userName:audio: AVAudioVoiceIO())`, and
   `await voice.start(pickup: true)` on a pickup (iPhone) or a notch tap (Mac); `await voice.stop()`
   when the island closes. Bind the notch to `state`, `lines` (with `languageLabel`), `card`,
   `activeIntent`, `activeFocus`, `timeUp` and `latencyMs`. With the fakes, use
   `VoiceModel.demo(scores: FakeScores(), cards: FakeZenCards())` and label it **Demo**; voice its
   lines with `onDemoLine` (AVSpeechSynthesizer, or the prototype's clips by `clip` name).
5. **Ask for the mic first**, with `AVAudioApplication.requestRecordPermission()`. If it's refused,
   `start` still connects and `voice.error` is `.disabled`; typed turns (`sendText`) still work.

Permissions and entitlements:

| Where | What |
|---|---|
| `iPhone/Info.plist` and `Mac/Info.plist` | `NSMicrophoneUsageDescription`, e.g. "Zeno listens when you tap it, so you can say what you picked up the phone for. Audio goes to Google Gemini for the reply and isn't stored." |
| `Mac/ZenModeOS.entitlements` | `com.apple.security.device.audio-input` = YES. The Mac app runs with the hardened runtime (no App Sandbox), which blocks the mic without it; it is the same key a sandboxed app needs. |
| Network | Outgoing WebSocket to `generativelanguage.googleapis.com`. Nothing to add without the sandbox; with one, `com.apple.security.network.client`. |
| iPhone audio | `AVAudioVoiceIO` sets the session to play-and-record, voice chat, speaker, with voice processing on (echo cancellation), and deactivates it on `stop()`. |
