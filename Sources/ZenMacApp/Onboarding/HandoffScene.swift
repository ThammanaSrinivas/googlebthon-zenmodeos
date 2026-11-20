import SwiftUI
import Albeit
import ZenAPI

// MARK: - The hand-off, drawn

/// This Mac and your iPhone, lit and dimensional, from signing in to the hand-off. On the sign-in
/// step Zeno waits in the iPhone's Dynamic Island while the Mac waits for you. On the hand-off Zeno
/// lifts out of the Island, travels on a trail of light into the Mac's notch, the notch opens around
/// it, and the score settles on the Mac to match the iPhone. Reduce Motion shows the arrival at once.
struct DeviceDuoStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False on the sign-in step, true on the hand-off.
    let handoff: Bool

    @State private var flightStart: Date?
    @State private var landed = false
    @State private var settled = false
    @State private var pulse = false

    static let canvas = CGSize(width: 760, height: 560)
    static let flightDuration = 1.45

    // The scene, in canvas points.
    private static let lid = CGRect(x: 180, y: 28, width: 540, height: 348)
    private static let screen = lid.insetBy(dx: 11, dy: 11)
    private static let phone = CGRect(x: 36, y: 150, width: 178, height: 372)
    private static let phoneScreen = phone.insetBy(dx: 9, dy: 9)
    private static let islandCenter = CGPoint(x: phone.midX, y: phoneScreen.minY + 20)
    private static let zenoInIsland = CGPoint(x: phone.midX - 30, y: islandCenter.y)
    private static let notchTop = CGPoint(x: lid.midX, y: screen.minY)
    private static let zenoFlightEnd = CGPoint(x: lid.midX, y: screen.minY + 13)
    private static let zenoInNotch = CGPoint(x: lid.midX - 100, y: screen.minY + 24)
    private static let flightControl = CGPoint(x: 150, y: -30)

    var body: some View {
        let score = (model.snapshot ?? FakeSnapshot.value).score.text
        GeometryReader { geo in
            let k = min(1, geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: flightStart == nil || landed)) { tl in
                scene(score: score, t: flightProgress(at: tl.date))
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .scaleEffect(k)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: handoff) { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(handoff
            ? "Your iPhone and this Mac both show Zen Score \(score). Zeno moved from the iPhone's Dynamic Island into the Mac's notch."
            : "Your iPhone, with Zeno in its Dynamic Island, and this Mac, waiting for you to sign in.")
    }

    // MARK: Timeline

    private func play() async {
        guard handoff else {
            flightStart = nil; landed = false; settled = false; pulse = false
            return
        }
        if reduceMotion {
            landed = true; settled = true
            return
        }
        try? await Task.sleep(for: .milliseconds(650))
        if Task.isCancelled { return }
        flightStart = Date()
        try? await Task.sleep(for: .seconds(Self.flightDuration))
        if Task.isCancelled { return }
        withAnimation(ZenMotion.zenoHappy) { landed = true }
        withAnimation(ZenMotion.calm(ZenMotion.t4)) { pulse = true }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(ZenMotion.settle(1.1)) { settled = true }
    }

    /// 0 in the Island, 1 at the notch, eased in and out.
    private func flightProgress(at date: Date) -> CGFloat {
        if landed { return 1 }
        guard let flightStart else { return 0 }
        let raw = min(1, max(0, date.timeIntervalSince(flightStart) / Self.flightDuration))
        // easeInOutCubic: a lift, a glide, a soft arrival.
        let e = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
        return CGFloat(e)
    }

    private static func point(_ t: CGFloat) -> CGPoint {
        let a = zenoInIsland, b = zenoFlightEnd, c = flightControl
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    // MARK: Scene

    private func scene(score: String, t: CGFloat) -> some View {
        let flying = t > 0 && !landed
        let left = t > 0.04 || landed
        return ZStack(alignment: .topLeading) {
            floorGlow
            mac(score: score)
            phone(score: score, zenoLeft: left)
            trail(t: t).opacity(flying ? 1 : 0)
            zeno(t: t)
            labels
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
    }

    /// A pool of green light under the devices; brighter once the day has arrived.
    private var floorGlow: some View {
        RadialGradient(colors: [Color.zen.brandSoft.opacity(settled ? 0.4 : 0.22), Color.zen.brandSoft.opacity(0.06), .clear],
                       center: .center, startRadius: 0, endRadius: 360)
            .frame(width: 740, height: 740)
            .scaleEffect(x: 1, y: 0.34)
            .position(x: 420, y: 420)
            .allowsHitTesting(false)
    }

    // MARK: The Mac

    private func mac(score: String) -> some View {
        let lid = Self.lid, screen = Self.screen
        return ZStack(alignment: .topLeading) {
            // A soft contact shadow where the base meets the desk.
            RadialGradient(colors: [Color.black.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 300)
                .frame(width: 620, height: 620)
                .scaleEffect(x: 1, y: 0.06)
                .position(x: lid.midX, y: lid.maxY + 16)
            // The lid: aluminium, a black bezel, the lit screen.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Metal.light, Metal.mid], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .frame(width: lid.width, height: lid.height)
                .offset(x: lid.minX, y: lid.minY)
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color(hex: 0x050605))
                .frame(width: lid.width - 6, height: lid.height - 6)
                .offset(x: lid.minX + 3, y: lid.minY + 3)
            macScreen(score: score)
                .frame(width: screen.width, height: screen.height)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .offset(x: screen.minX, y: screen.minY)
            notch(score: score)
            // The base: a thin slab that catches the light, with the thumb groove.
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: [Metal.light, Metal.mid, Metal.dark], startPoint: .top, endPoint: .bottom))
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
                    .fill(Metal.dark.opacity(0.7))
                    .frame(width: 96, height: 5)
                Rectangle().fill(.white.opacity(0.6)).frame(height: 1).padding(.horizontal, 6)
            }
            .frame(width: lid.width + 64, height: 15)
            .offset(x: lid.minX - 32, y: lid.maxY)
        }
    }

    private func macScreen(score: String) -> some View {
        ZStack {
            ScreenGlow(tilt: 0.2)
            VStack(spacing: 0) {
                // The menu bar, with ZenMode OS's menus on the left.
                HStack(spacing: 14) {
                    ZenMark().fill(Color.zen.islandText, style: FillStyle(eoFill: true)).frame(width: 9, height: 9)
                    Text(Copy.product).font(ZenFont.text(9.5, .semibold)).foregroundStyle(Color.zen.islandText)
                    Text("Today").font(ZenFont.text(9.5)).foregroundStyle(Color.zen.islandDetail)
                    Text("Week").font(ZenFont.text(9.5)).foregroundStyle(Color.zen.islandDetail)
                    Spacer()
                    Capsule().fill(Color.zen.islandDetail.opacity(0.6)).frame(width: 16, height: 7)
                    Circle().fill(Color.zen.islandDetail.opacity(0.6)).frame(width: 7, height: 7)
                }
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Color.white.opacity(0.05))
                Spacer()
                VStack(spacing: 10) {
                    Text("ZEN SCORE · TODAY").font(ZenFont.number(9.5)).tracking(1.1).foregroundStyle(Color.zen.islandDetail)
                    ZStack {
                        Text("–.–").font(ZenFont.number(88)).foregroundStyle(Color.zen.islandDetail.opacity(0.35))
                            .opacity(settled ? 0 : 1)
                        ScoreText(score, size: 88)
                            .shadow(color: Color.zen.brandSoft.opacity(settled ? 0.35 : 0), radius: 18)
                            .opacity(settled ? 1 : 0)
                            .blur(radius: settled ? 0 : 10)
                            .scaleEffect(settled ? 1 : 1.14)
                    }
                    Text(settled ? Copy.Handoff.arrived : (handoff ? Copy.Handoff.arriving : Copy.Bring.waiting))
                        .font(ZenFont.text(12, .medium)).foregroundStyle(Color.zen.islandText.opacity(0.82))
                        .contentTransition(.opacity)
                    WeekCapsules(week: (model.snapshot ?? FakeSnapshot.value).week, lit: settled)
                        .padding(.top, 6)
                }
                Spacer()
                Spacer().frame(height: 18)
            }
        }
    }

    private func notch(score: String) -> some View {
        let w: CGFloat = landed ? 262 : 98
        let h: CGFloat = landed ? 48 : 24
        return ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: landed ? 22 : 10, bottomTrailingRadius: landed ? 22 : 10, style: .continuous)
                .fill(Color.zen.island)
                .shadow(color: Color.zen.brandSoft.opacity(landed ? 0.35 : 0), radius: 14, y: 4)
            if landed {
                HStack(spacing: 8) {
                    Spacer().frame(width: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.Handoff.kicker.uppercased()).font(ZenFont.number(7.5)).tracking(0.8).foregroundStyle(Color.zen.islandDetail)
                        Text(Copy.Handoff.arrivedLine).font(ZenFont.text(11.5, .semibold)).foregroundStyle(Color.zen.islandText)
                    }
                    Spacer(minLength: 0)
                    Text(score).font(ZenFont.number(15)).foregroundStyle(Color.zen.brandSoft)
                }
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: w, height: h)
        // The landing: one ring of light.
        .background {
            Capsule().strokeBorder(Color.zen.brandSoft.opacity(pulse ? 0 : 0.8), lineWidth: 2)
                .frame(width: w, height: h)
                .scaleEffect(pulse ? 1.7 : 0.9)
                .opacity(landed ? 1 : 0)
        }
        .position(x: Self.notchTop.x, y: Self.notchTop.y + h / 2)
    }

    // MARK: The iPhone

    private func phone(score: String, zenoLeft: Bool) -> some View {
        let phone = Self.phone, screen = Self.phoneScreen
        return ZStack(alignment: .topLeading) {
            // Titanium band, with light catching the edge.
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(LinearGradient(colors: [Metal.light, Metal.dark, Metal.mid, Metal.light], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: phone.width, height: phone.height)
                .offset(x: phone.minX, y: phone.minY)
                .shadow(color: .black.opacity(0.3), radius: 26, x: 8, y: 18)
            RoundedRectangle(cornerRadius: 41, style: .continuous)
                .fill(Color(hex: 0x050605))
                .frame(width: phone.width - 6, height: phone.height - 6)
                .offset(x: phone.minX + 3, y: phone.minY + 3)
            phoneScreen(score: score)
                .frame(width: screen.width, height: screen.height)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .offset(x: screen.minX, y: screen.minY)
            // The Dynamic Island: Zeno on the left until it leaves, the score on the right.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(score).font(ZenFont.number(12)).foregroundStyle(Color.zen.brandSoft)
            }
            .padding(.horizontal, 11)
            .frame(width: zenoLeft ? 92 : 112, height: 30)
            .background(Capsule().fill(Color.zen.island))
            .position(Self.islandCenter)
            .animation(ZenMotion.container, value: zenoLeft)
            // A glint along the band.
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .clear, .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .frame(width: phone.width, height: phone.height)
                .offset(x: phone.minX, y: phone.minY)
        }
    }

    private func phoneScreen(score: String) -> some View {
        ZStack {
            ScreenGlow(tilt: -0.3)
            VStack(spacing: 6) {
                Spacer().frame(height: 74)
                Text("ZEN SCORE").font(ZenFont.number(8.5)).tracking(1.1).foregroundStyle(Color.zen.islandDetail)
                ScoreText(score, size: 54)
                Text("today").font(ZenFont.text(11, .medium)).foregroundStyle(Color.zen.islandText.opacity(0.8))
                Spacer()
                WeekCapsules(week: (model.snapshot ?? FakeSnapshot.value).week, lit: true, compact: true)
                Spacer().frame(height: 26)
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 54, height: 4)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: Zeno and the trail

    private func zeno(t: CGFloat) -> some View {
        let p: CGPoint = landed ? Self.zenoInNotch : Self.point(t)
        let base: CGFloat = landed ? 38 : 24 + 8 * t
        let width = base + (landed ? 0 : 34 * sin(.pi * t))
        return ZenoView(t > 0.5 || landed ? .happy : .pleasant)
            .frame(width: width)
            .shadow(color: Color.zen.brandSoft.opacity(t > 0 && !landed ? 0.7 : 0), radius: 14)
            .position(p)
    }

    private func trail(t: CGFloat) -> some View {
        let path = Path { p in
            p.move(to: Self.zenoInIsland)
            p.addQuadCurve(to: Self.zenoFlightEnd, control: Self.flightControl)
        }
        return ZStack {
            path.trim(from: max(0, t - 0.42), to: t)
                .stroke(Color.zen.brandSoft.opacity(0.5), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .blur(radius: 9)
            path.trim(from: max(0, t - 0.32), to: t)
                .stroke(LinearGradient(colors: [Color.zen.brandSoft.opacity(0), Color.zen.brandSoft, .white],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            ForEach(1..<5, id: \.self) { i in
                let s = max(0, t - CGFloat(i) * 0.07)
                Circle().fill(Color.white.opacity(0.9 - Double(i) * 0.18))
                    .frame(width: 5 - CGFloat(i) * 0.8, height: 5 - CGFloat(i) * 0.8)
                    .position(Self.point(s))
                    .offset(x: CGFloat(i % 2 == 0 ? 5 : -5), y: CGFloat(i % 2 == 0 ? -4 : 6))
            }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .allowsHitTesting(false)
    }

    private var labels: some View {
        ZStack(alignment: .topLeading) {
            DeviceLabel(symbol: "iphone", text: Copy.Handoff.iPhone)
                .position(x: Self.phone.midX, y: Self.phone.maxY + 22)
            DeviceLabel(symbol: "laptopcomputer", text: Copy.Handoff.mac)
                .position(x: Self.lid.midX + 40, y: Self.lid.maxY + 48)
        }
    }
}

/// The aluminium and titanium: light and dark ends of the same metal, in both appearances.
private enum Metal {
    static let light = Color(light: 0xF1F1EE, dark: 0x6A6D68)
    static let mid = Color(light: 0xC9CBC5, dark: 0x3A3D39)
    static let dark = Color(light: 0x9C9E98, dark: 0x1F211E)
}

/// The lit glass of a screen: ink with ZenMode OS's green aurora rising from below.
private struct ScreenGlow: View {
    let tilt: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B120C), Color(hex: 0x0E1A10)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.zen.brandFill.opacity(0.55), .clear], center: UnitPoint(x: 0.5 + tilt * 0.3, y: 1.15),
                           startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color.zen.accentReward.opacity(0.12), .clear], center: UnitPoint(x: 0.92, y: 0.0),
                           startRadius: 0, endRadius: 200)
            // Glare across the glass.
            LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.6))
        }
    }
}

/// The week, as seven capsules: green for a good day, a ring for a day still to come.
private struct WeekCapsules: View {
    let week: WeekProgress
    var lit: Bool
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(0..<7, id: \.self) { d in
                let day = week.days[d]
                let good = day?.isGoodDay ?? false
                Capsule()
                    .fill(day == nil ? Color.clear : (good && lit ? Color.zen.brandSoft : Color.white.opacity(0.22)))
                    .overlay { if day == nil { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1) } }
                    .frame(width: compact ? 10 : 18, height: compact ? 4 : 6)
                    .shadow(color: good && lit ? Color.zen.brandSoft.opacity(0.6) : .clear, radius: 4)
            }
        }
    }
}

private struct DeviceLabel: View {
    let symbol: String, text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text).font(ZenFont.text(12.5, .semibold))
        }
        .foregroundStyle(Color.zen.textBody)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .glassEffect(.regular, in: .capsule)
    }
}
