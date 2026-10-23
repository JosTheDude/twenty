import SwiftUI

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
