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
    @AppStorage(Key.warnSound) private var warnSound = "Tink"
    @AppStorage(Key.chime) private var chime = true
    @AppStorage(Key.holdInCalls) private var holdInCalls = true
    @AppStorage(Key.streak) private var streak = 0
    @AppStorage(Key.best) private var best = 0
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    // Set by a configuration profile, so edits here would be ignored.
    private func managed(_ key: String) -> Bool { UserDefaults.standard.objectIsForced(forKey: key) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Break every") {
                    Stepper(value: $work, in: 5...120, step: 5) { Text("\(Int(work)) min").monospacedDigit() }
                        .disabled(managed(Key.work))
                }
                LabeledContent("Break length") {
                    Stepper(value: $rest, in: 10...300, step: 5) { Text("\(Int(rest)) sec").monospacedDigit() }
                        .disabled(managed(Key.rest))
                }
                Picker("Heads-up", selection: $warn) {
                    Text("Off").tag(0.0)
                    Text("15 seconds before").tag(15.0)
                    Text("30 seconds before").tag(30.0)
                    Text("1 minute before").tag(60.0)
                    Text("2 minutes before").tag(120.0)
                }
                .disabled(managed(Key.warn))
                Picker("Heads-up sound", selection: $warnSound) {
                    Text("None").tag("")
                    ForEach(["Tink", "Pop", "Ping", "Purr", "Glass", "Hero"], id: \.self) { Text($0).tag($0) }
                }
                .disabled(managed(Key.warnSound) || warn == 0)
                .onChange(of: warnSound) { NSSound(named: warnSound)?.play() }
                Toggle("Chime when a break ends", isOn: $chime)
                    .disabled(managed(Key.chime))
            }

            Section {
                Toggle("Hold breaks during calls", isOn: $holdInCalls)
                    .disabled(managed(Key.holdInCalls))
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
