import SwiftUI
import ServiceManagement
import CoreAudio
import CoreMediaIO

// Settings keys. Any of them can be overridden for testing, e.g. `Twenty -workMinutes 0.1`
enum Key {
    static let work = "workMinutes", rest = "breakSeconds", warn = "warnSeconds"
    static let chime = "chime", holdInCalls = "holdInCalls", streak = "streak", best = "bestStreak"
}

@main
struct TwentyApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: menuBarIcon(paused: model.paused))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

// One-shot timers only, so the app does nothing between breaks.
@MainActor
final class Model: ObservableObject {
    @Published private(set) var nextBreak = Date()
    @Published private(set) var breakEnds: Date?
    @Published private(set) var paused = false
    @Published private(set) var waiting = false // break is due, but you're in a call
    private var pausedLeft: TimeInterval = 0
    private var timer: Timer?
    private var warnTimer: Timer?
    private var overlays: [NSWindow] = []
    private var warning: NSWindow?
    private var previousApp: NSRunningApplication?
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [Key.work: 20.0, Key.rest: 20.0, Key.warn: 60.0, Key.chime: true, Key.holdInCalls: true])
        restart()
        // Screen was off, eyes were rested: start a fresh interval.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.paused else { return }
                self.closeBreak()
                self.restart()
            }
        }
    }

    private var workInterval: TimeInterval { defaults.double(forKey: Key.work) * 60 }
    var remaining: TimeInterval { paused ? pausedLeft : max(0, nextBreak.timeIntervalSinceNow) }

    func restart() {
        if !paused && breakEnds == nil { schedule(in: workInterval) }
    }

    func togglePause() {
        if paused {
            paused = false
            schedule(in: pausedLeft)
        } else {
            pausedLeft = breakEnds != nil ? workInterval : remaining
            closeBreak()
            stopTimers()
            paused = true
        }
    }

    func startBreak() {
        stopTimers()
        paused = false
        let length = defaults.double(forKey: Key.rest)
        breakEnds = Date().addingTimeInterval(length)
        timer = fire(after: length) { $0.completeBreak() }
        showOverlays()
    }

    func skipBreak() {
        defaults.set(0, forKey: Key.streak)
        closeBreak()
        restart()
    }

    private func completeBreak() {
        let streak = defaults.integer(forKey: Key.streak) + 1
        defaults.set(streak, forKey: Key.streak)
        defaults.set(max(streak, defaults.integer(forKey: Key.best)), forKey: Key.best)
        if defaults.bool(forKey: Key.chime) { NSSound(named: "Glass")?.play() }
        closeBreak()
        restart()
    }

    private var holding: Bool { defaults.bool(forKey: Key.holdInCalls) && (cameraInUse() || micInUse()) }

    private func breakDue() {
        guard holding else { return startBreak() }
        hideWarning()
        waiting = true
        timer = fire(after: 30) { $0.breakDue() }
    }

    private func schedule(in seconds: TimeInterval) {
        stopTimers()
        nextBreak = Date().addingTimeInterval(seconds)
        timer = fire(after: seconds) { $0.breakDue() }
        let warn = defaults.double(forKey: Key.warn)
        if warn > 0 { warnTimer = fire(after: max(0, seconds - warn)) { $0.showWarning() } }
    }

    private func stopTimers() {
        timer?.invalidate()
        warnTimer?.invalidate()
        waiting = false
        hideWarning()
    }

    private func fire(after seconds: TimeInterval, _ action: @escaping (Model) -> Void) -> Timer {
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        t.tolerance = 0.2
        return t
    }

    private func fade(_ windows: [NSWindow], in fadeIn: Bool) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeIn ? 0.6 : 0.5
            windows.forEach { $0.animator().alphaValue = fadeIn ? 1 : 0 }
        }, completionHandler: { if !fadeIn { windows.forEach { $0.close() } } })
    }

    private func showOverlays() {
        guard overlays.isEmpty, let ends = breakEnds else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let streak = defaults.integer(forKey: Key.streak)
        overlays = NSScreen.screens.map { screen in
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: BreakView(ends: ends, streak: streak) { [weak self] in self?.skipBreak() })
            w.setFrame(screen.frame, display: false)
            w.alphaValue = 0
            w.orderFrontRegardless()
            return w
        }
        overlays.first?.makeKey()
        NSApp.activate() // so Esc reaches the Skip button
        fade(overlays, in: true)
    }

    private func closeBreak() {
        breakEnds = nil
        guard !overlays.isEmpty else { return }
        fade(overlays, in: false)
        overlays = []
        previousApp?.activate()
    }

    // A small pill under the menu bar that never takes focus or clicks.
    private func showWarning() {
        guard warning == nil, !holding, let screen = NSScreen.main else { return }
        let size = NSSize(width: 184, height: 34), f = screen.visibleFrame
        let p = NSPanel(contentRect: NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 10, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.appearance = NSAppearance(named: .darkAqua)
        let blur = Blur.view(.hudWindow)
        blur.maskImage = NSImage(size: size, flipped: false) { r in
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
            return true
        }
        p.contentView = blur
        let host = NSHostingView(rootView: WarningView(at: nextBreak))
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        p.alphaValue = 0
        p.orderFrontRegardless()
        warning = p
        fade([p], in: true)
    }

    private func hideWarning() {
        guard let w = warning else { return }
        fade([w], in: false)
        warning = nil
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Call detection (no permissions needed: these only ask whether a device is busy)

func cameraInUse() -> Bool {
    let system = CMIOObjectID(kCMIOObjectSystemObject)
    var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0 else { return false }
    var ids = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
    guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &size, &ids) == 0 else { return false }
    addr.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
    return ids.contains { id in
        var running: UInt32 = 0, s = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(id, &addr, 0, nil, s, &s, &running) == 0 && running != 0
    }
}

// Per-process input check, so music playing on AirPods doesn't count as a call.
func micInUse() -> Bool {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return false }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return false }
    addr.mSelector = kAudioProcessPropertyIsRunningInput
    return ids.contains { id in
        var running: UInt32 = 0, s = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &s, &running) == noErr && running != 0
    }
}

// MARK: - Views

// The app icon's mark (see icon.swift) as a menu bar template; paused shows the eye closed.
func menuBarIcon(paused: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { _ in
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * 20, y: y * 20 - 3) }
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: p(0.04, 0.5))
        if !paused {
            path.curve(to: p(0.96, 0.5), controlPoint1: p(0.3, 0.86), controlPoint2: p(0.7, 0.86))
        } else {
            path.move(to: p(0.96, 0.5))
        }
        path.curve(to: p(0.04, 0.5), controlPoint1: p(0.7, 0.14), controlPoint2: p(0.3, 0.14))
        if !paused {
            path.close()
            path.move(to: p(0.5, 0.655))
            path.appendArc(withCenter: p(0.5, 0.5), radius: 3.1, startAngle: 90, endAngle: -150, clockwise: true)
            path.appendOval(in: NSRect(origin: p(0.5, 0.5), size: .zero).insetBy(dx: -0.9, dy: -0.9))
        }
        NSColor.black.set()
        path.stroke()
        return true
    }
    img.isTemplate = true
    return img
}

func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded(.up)))
    return String(format: "%d:%02d", s / 60, s % 60)
}

struct MenuView: View {
    @ObservedObject var model: Model
    @AppStorage(Key.streak) private var streak = 0
    @AppStorage(Key.best) private var best = 0
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.breakEnds != nil ? "On a break"
                         : model.paused ? "Paused"
                         : model.waiting ? "Break waits until your call ends"
                         : "Next break in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(model.waiting ? "In a call" : clock(model.remaining))
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.paused ? .secondary : .primary)
                }
            }

            HStack(spacing: 8) {
                Button(model.paused ? "Resume" : "Pause") { model.togglePause() }
                    .frame(maxWidth: .infinity)
                Button("Break now") { model.startBreak() }
                    .frame(maxWidth: .infinity)
                    .disabled(model.breakEnds != nil)
            }
            .controlSize(.large)

            HStack {
                Label {
                    Text("\(streak) in a row")
                } icon: {
                    Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? .orange : .secondary)
                }
                Spacer()
                Text("Best \(best)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .monospacedDigit()

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 248)
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    @AppStorage(Key.work) private var work = 20.0
    @AppStorage(Key.rest) private var rest = 20.0
    @AppStorage(Key.warn) private var warn = 60.0
    @AppStorage(Key.chime) private var chime = true
    @AppStorage(Key.holdInCalls) private var holdInCalls = true
    @AppStorage(Key.streak) private var streak = 0
    @AppStorage(Key.best) private var best = 0
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Break every") {
                    Stepper(value: $work, in: 5...120, step: 5) { Text("\(Int(work)) min").monospacedDigit() }
                }
                LabeledContent("Break length") {
                    Stepper(value: $rest, in: 10...300, step: 5) { Text("\(Int(rest)) sec").monospacedDigit() }
                }
                Picker("Heads-up", selection: $warn) {
                    Text("Off").tag(0.0)
                    Text("15 seconds before").tag(15.0)
                    Text("30 seconds before").tag(30.0)
                    Text("1 minute before").tag(60.0)
                    Text("2 minutes before").tag(120.0)
                }
                Toggle("Chime when a break ends", isOn: $chime)
            }

            Section {
                Toggle("Hold breaks during calls", isOn: $holdInCalls)
            } footer: {
                Text("Waits while your camera or microphone is in use, then takes the break once you're done.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Current streak", value: "\(streak)")
                LabeledContent("Best streak", value: "\(best)")
                Button("Reset Streaks") { streak = 0; best = 0 }
            } footer: {
                Text("Every finished break adds one. Skipping a break starts over.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: work) { model.restart() }
        .onChange(of: warn) { model.restart() }
    }
}

struct WarningView: View {
    let at: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Label("Eye break in \(clock(at.timeIntervalSince(ctx.date)))", systemImage: "eye")
        }
        .font(.system(size: 13, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BreakView: View {
    let ends: Date
    let streak: Int
    let skip: () -> Void
    @State private var progress = 1.0

    var body: some View {
        ZStack {
            Blur().ignoresSafeArea()
            Color.black.opacity(0.3).ignoresSafeArea()

            VStack(spacing: 32) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(max(0, Int(ends.timeIntervalSince(ctx.date).rounded(.up))))")
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .frame(width: 112, height: 112)

                VStack(spacing: 10) {
                    Text("Look away")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("Rest your eyes on something 20 feet away.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(spacing: 6) {
                    Button("Skip", action: skip)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .keyboardShortcut(.cancelAction)
                    if streak > 0 {
                        Text("Skipping ends your \(streak)-break streak")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.linear(duration: ends.timeIntervalSinceNow)) { progress = 0 }
        }
    }
}

struct Blur: NSViewRepresentable {
    static func view(_ material: NSVisualEffectView.Material) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func makeNSView(context: Context) -> NSVisualEffectView { Self.view(.fullScreenUI) }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
