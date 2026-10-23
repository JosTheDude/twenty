import SwiftUI
import UserNotifications

// One-shot timers only, so the app does nothing between breaks.
@MainActor
final class Model: ObservableObject {
    @Published private(set) var nextBreak = Date()
    @Published private(set) var breakEnds: Date?
    @Published private(set) var paused = false
    @Published private(set) var waiting = false // break is due, but you're in a call
    private var pausedLeft: TimeInterval = 0
    private var intervalStart = Date()
    private var timer: Timer?
    private var warnTimer: Timer?
    private var overlays: [NSWindow] = []
    private var warning: NSWindow?
    private var previousApp: NSRunningApplication?
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [Key.work: 20.0, Key.rest: 20.0, Key.warn: 60.0, Key.warnSound: "Tink", Key.chime: true, Key.holdInCalls: true])
        restart()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        // Screen off: nobody is looking, so no break runs and none counts toward the streak.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeBreak()
                self?.stopTimers()
            }
        }
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

    // No keyboard or mouse input all interval, so there's nothing to rest from.
    private var away: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            >= -intervalStart.timeIntervalSinceNow
    }

    private var holding: Bool { defaults.bool(forKey: Key.holdInCalls) && (cameraInUse() || micInUse()) }

    private func breakDue() {
        if away { return restart() }
        guard holding else { return startBreak() }
        hideWarning()
        waiting = true
        timer = fire(after: 30) { $0.breakDue() }
    }

    private func schedule(in seconds: TimeInterval) {
        stopTimers()
        intervalStart = Date()
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
        guard warning == nil, !holding, !away, let screen = NSScreen.main else { return }
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
        defaults.string(forKey: Key.warnSound).flatMap { NSSound(named: $0) }?.play()
        let note = UNMutableNotificationContent() // silent: the heads-up sound above covers it
        note.title = "Eye break in \(clock(nextBreak.timeIntervalSinceNow))"
        note.body = "Get ready to look away for a moment."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "heads-up", content: note, trigger: nil))
        fade([p], in: true)
    }

    private func hideWarning() {
        guard let w = warning else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["heads-up"])
        fade([w], in: false)
        warning = nil
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
