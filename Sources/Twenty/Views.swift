import SwiftUI
import ServiceManagement

// The app icon's mark (see scripts/icon.swift) as a menu bar template; paused shows the eye closed.
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
                         : model.waiting ? "Break waits until your call or video ends"
                         : "Next break in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(model.waiting ? "Busy" : clock(model.remaining))
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.paused ? .secondary : .primary)
                }
            }

            HStack(spacing: 8) {
                Button(model.paused ? "Resume" : "Pause") { model.togglePause() }
                    .frame(maxWidth: .infinity)
                    .modifier(HoverLift())
                Button("Break now") { model.startBreak() }
                    .frame(maxWidth: .infinity)
                    .disabled(model.breakEnds != nil)
                    .modifier(HoverLift())
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
                .modifier(HoverLift(rest: .secondary))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .modifier(HoverLift(rest: .secondary))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 248)
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    @AppStorage(Key.work) private var work = 20.0
    @AppStorage(Key.rest) private var rest = 20.0
    @AppStorage(Key.snooze) private var snooze = 5.0
    @AppStorage(Key.warn) private var warn = 60.0
    @AppStorage(Key.glow) private var glow = 8.0
    @AppStorage(Key.glowWidth) private var glowWidth = 160.0
    @AppStorage(Key.warnSound) private var warnSound = "Tink"
    @AppStorage(Key.chime) private var chime = true
    @AppStorage(Key.holdInCalls) private var holdInCalls = true
    @AppStorage(Key.video) private var video = "quiet"
    @AppStorage(Key.streak) private var streak = 0
    @AppStorage(Key.best) private var best = 0
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    // Set by a configuration profile, so edits here would be ignored.
    private func managed(_ key: String) -> Bool { UserDefaults.standard.objectIsForced(forKey: key) }

    var body: some View {
        Form {
            Section("Breaks") {
                TimePicker("Break every", unit: "min", min: 1, value: $work, disabled: managed(Key.work),
                           presets: [("10 minutes", 10), ("15 minutes", 15), ("20 minutes", 20), ("30 minutes", 30), ("45 minutes", 45), ("1 hour", 60)])
                TimePicker("Break length", unit: "sec", min: 5, value: $rest, disabled: managed(Key.rest),
                           presets: [("10 seconds", 10), ("20 seconds", 20), ("30 seconds", 30), ("1 minute", 60)])
                TimePicker("Snooze for", unit: "min", min: 1, value: $snooze, disabled: managed(Key.snooze),
                           presets: [("1 minute", 1), ("5 minutes", 5), ("10 minutes", 10), ("15 minutes", 15)])
                Toggle("Chime when a break ends", isOn: $chime)
                    .disabled(managed(Key.chime))
            }

            Section("Heads-up") {
                TimePicker("Heads-up", unit: "sec", min: 0, value: $warn, disabled: managed(Key.warn),
                           presets: [("Off", 0), ("15 seconds before", 15), ("30 seconds before", 30), ("1 minute before", 60), ("2 minutes before", 120)])
                Picker("Heads-up sound", selection: $warnSound) {
                    Text("None").tag("")
                    ForEach(["Tink", "Pop", "Ping", "Purr", "Glass", "Hero"], id: \.self) { Text($0).tag($0) }
                }
                .disabled(managed(Key.warnSound) || warn == 0)
                .onChange(of: warnSound) { NSSound(named: warnSound)?.play() }
            }

            Section {
                TimePicker("Edge glow", unit: "sec", min: 0, value: $glow, disabled: managed(Key.glow),
                           presets: [("Off", 0), ("3 seconds before", 3), ("5 seconds before", 5), ("8 seconds before", 8), ("15 seconds before", 15)])
                Picker("Edge glow size", selection: $glowWidth) {
                    Text("Subtle").tag(80.0)
                    Text("Medium").tag(160.0)
                    Text("Bold").tag(320.0)
                }
                .disabled(managed(Key.glowWidth) || glow == 0)
            } header: {
                Text("Edge glow")
            } footer: {
                Text("The sides of the screen pulse softly in the last seconds before a break.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hold breaks during calls", isOn: $holdInCalls)
                    .disabled(managed(Key.holdInCalls))
                Picker("While video plays", selection: $video) {
                    Text("Break as usual").tag("break")
                    Text("Quiet reminder").tag("quiet")
                    Text("Hold the break").tag("hold")
                }
                .disabled(managed(Key.video))
            } footer: {
                Text("Calls wait for your camera or microphone to go quiet. A quiet reminder is a small countdown under the menu bar that never covers the video.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Current streak", value: "\(streak)")
                LabeledContent("Best streak", value: "\(best)")
                Button("Reset Streaks") { streak = 0; best = 0 }
            } footer: {
                Text("Every finished break adds one. Skipping a break starts over; snoozing doesn't.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }

            Section("About") {
                LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: work) { model.restart() }
        .onChange(of: warn) { model.restart() }
        .onChange(of: glow) { model.restart() }
        .onChange(of: rest) { model.restart() }
    }
}

// Preset menu with a Custom… entry that reveals a number field. Values below `min` are clamped.
struct TimePicker: View {
    let title: String, unit: String, min: Double, presets: [(String, Double)], disabled: Bool
    @Binding var value: Double
    @State private var custom: Bool

    init(_ title: String, unit: String, min: Double, value: Binding<Double>, disabled: Bool, presets: [(String, Double)]) {
        self.title = title; self.unit = unit; self.min = min; self.presets = presets; self.disabled = disabled
        _value = value
        _custom = State(initialValue: !presets.contains { $0.1 == value.wrappedValue })
    }

    var body: some View {
        Picker(title, selection: Binding(get: { custom ? -1 : value }, set: { custom = $0 < 0; if $0 >= 0 { value = $0 } })) {
            ForEach(presets, id: \.1) { Text($0.0).tag($0.1) }
            Divider()
            Text("Custom…").tag(-1.0)
        }
        .disabled(disabled)
        if custom {
            LabeledContent("Custom \(title.lowercased())") {
                HStack(spacing: 4) {
                    TextField("", value: Binding(get: { value }, set: { value = Swift.max(min, $0) }), format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            .disabled(disabled)
        }
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

// Core Animation runs these in the render server, so the app does no per-frame work.
func edgeGlow(right: Bool) -> NSView {
    let v = NSView()
    v.wantsLayer = true
    let g = CAGradientLayer()
    g.colors = [NSColor.white.withAlphaComponent(0.4).cgColor, NSColor.clear.cgColor]
    g.startPoint = CGPoint(x: right ? 1 : 0, y: 0.5)
    g.endPoint = CGPoint(x: right ? 0 : 1, y: 0.5)
    g.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    let pulse = CABasicAnimation(keyPath: "opacity")
    pulse.fromValue = 0.2
    pulse.toValue = 1
    pulse.duration = 0.75
    pulse.autoreverses = true
    pulse.repeatCount = .infinity
    pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    g.add(pulse, forKey: nil)
    v.layer?.addSublayer(g)
    return v
}

struct Ring: NSViewRepresentable {
    let duration: TimeInterval

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 112, height: 112))
        v.wantsLayer = true
        let path = CGMutablePath() // from 12 o'clock, clockwise
        path.addArc(center: CGPoint(x: 56, y: 56), radius: 54.5, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for (alpha, animated) in [(0.12, false), (1.0, true)] {
            let s = CAShapeLayer()
            s.path = path
            s.fillColor = nil
            s.strokeColor = NSColor.white.withAlphaComponent(alpha).cgColor
            s.lineWidth = 3
            s.lineCap = .round
            if animated {
                s.strokeEnd = 0
                let drain = CABasicAnimation(keyPath: "strokeEnd")
                drain.fromValue = 1
                drain.toValue = 0
                drain.duration = duration
                s.add(drain, forKey: nil)
            }
            v.layer?.addSublayer(s)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Turns a button bright and nudges it larger while the pointer is over it.
struct HoverLift: ViewModifier {
    var rest: Color? = nil
    var lit: Color = .primary
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(on || rest == nil ? lit : rest!)
            .scaleEffect(on ? 1.06 : 1)
            .animation(.snappy(duration: 0.15), value: on)
            .onHover { on = $0 }
    }
}

struct QuietBreakView: View {
    let ends: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Label("Look away · \(clock(ends.timeIntervalSince(ctx.date)))", systemImage: "eye")
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
    let snoozeMinutes: Double
    let snooze: () -> Void
    let skip: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Blur().ignoresSafeArea()
            Color.black.opacity(0.3).ignoresSafeArea()

            VStack(spacing: 32) {
                ZStack {
                    Ring(duration: ends.timeIntervalSinceNow)
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
                    HStack(spacing: 20) {
                        Button("Snooze \(snoozeMinutes.formatted()) min", action: snooze)
                            .modifier(HoverLift(rest: .white.opacity(0.45), lit: .white))
                        Button("Skip", action: skip)
                            .keyboardShortcut(.cancelAction)
                            .modifier(HoverLift(rest: .white.opacity(0.45), lit: .white))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    if streak > 0 {
                        Text("Skipping ends your \(streak)-break streak")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .foregroundStyle(.white)
            .scaleEffect(shown ? 1 : 1.08)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.15)) { shown = true }
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
