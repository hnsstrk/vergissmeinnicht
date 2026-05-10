import SwiftUI
import VergissmeinnichtKit

@main
struct VergissmeinnichtApp: App {
    @State private var container: AppContainer

    init() {
        do {
            _container = State(initialValue: try AppContainer())
        } catch {
            fatalError("Konnte App-Container nicht initialisieren: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Vergissmeinnicht") {
            RootView()
                .environment(container)
        }

        MenuBarExtra("Vergissmeinnicht", systemImage: "checkmark.circle") {
            QuickCaptureSheet()
                .environment(container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(container)
        }
    }
}
