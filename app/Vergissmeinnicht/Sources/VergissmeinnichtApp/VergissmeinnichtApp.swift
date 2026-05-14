import SwiftUI
import VergissmeinnichtKit

/// Menü-Befehl, der per `NotificationCenter` vom Menübalken an RootView durchgereicht wird.
enum AppCommand {
    case newTask
    case markDoneSelection
    case deleteSelection
    case openDetail
}

extension Notification.Name {
    static let vmCommand = Notification.Name("vergissmeinnicht.command")
}

@main
struct VergissmeinnichtApp: App {
    @State private var container: AppContainer?
    @State private var initError: String?
    @State private var showShortcuts = false

    init() {
        // Sprach-Override muss VOR App-Body-Init in `AppleLanguages` stehen,
        // damit Bundle/Localizable.xcstrings sie respektiert. Wirksam ab dem
        // jetzigen Launch.
        AppLanguage.applyAtLaunch()

        do {
            _container = State(initialValue: try AppContainer())
        } catch {
            _container = State(initialValue: nil)
            _initError = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup("Vergissmeinnicht") {
            if let container {
                RootView()
                    .environment(container)
                    .sheet(isPresented: $showShortcuts) {
                        ShortcutHelpView()
                    }
            } else {
                InitErrorView(message: initError ?? "Unbekannter Fehler") {
                    do {
                        container = try AppContainer()
                        initError = nil
                    } catch {
                        initError = String(describing: error)
                    }
                }
            }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Tastenkürzel") {
                    showShortcuts = true
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {
                Button("Neue Aufgabe …") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.newTask)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(container == nil)
                Divider()
                Button("Aktualisieren") {
                    if let container { Task { await container.refresh() } }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(container == nil)
                Button("Synchronisieren") {
                    if let container { Task { await container.syncIfConfigured() } }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(container == nil)
            }
            CommandMenu("Aufgabe") {
                Button("Als erledigt markieren") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.markDoneSelection)
                }
                .keyboardShortcut("d", modifiers: .command)
                Button("Löschen") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.deleteSelection)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("Detail öffnen") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.openDetail)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }

        WindowGroup("Task-Detail", id: "task-detail", for: String.self) { $uuid in
            if let container {
                TaskDetailWindow(uuid: uuid)
                    .environment(container)
            } else {
                Text("App nicht initialisiert.")
            }
        }

        Window("Über Vergissmeinnicht", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Vergissmeinnicht", systemImage: "checkmark.circle") {
            if let container {
                QuickCaptureSheet()
                    .environment(container)
            } else {
                Text("App nicht initialisiert.")
                    .padding()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let container {
                SettingsView()
                    .environment(container)
            } else {
                Text("App nicht initialisiert.")
                    .padding()
            }
        }
    }
}

/// Wird angezeigt, wenn `AppContainer.init` fehlschlägt — typischerweise SQLite-Storage-
/// Probleme (Sandbox-Migration, Disk voll, Permissions). Bietet Retry und Pfad-Anzeige.
struct InitErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Vergissmeinnicht konnte nicht starten")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .textSelection(.enabled)
            Button("Erneut versuchen") { onRetry() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(minWidth: 440, minHeight: 320)
    }
}
