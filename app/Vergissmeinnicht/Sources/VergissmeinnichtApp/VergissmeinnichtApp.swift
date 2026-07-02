import SwiftUI
import VergissmeinnichtKit

/// Menü-Befehl, der per `NotificationCenter` vom Menübalken an RootView durchgereicht wird.
enum AppCommand {
    case newTask
    case markDoneSelection
    case deleteSelection
    case openDetail
    /// Wechselt die Hauptliste auf einen der nativen Abhängigkeits-Reports
    /// (Taskwarrior `+BLOCKED`/`+BLOCKING`/`+UNBLOCKED`).
    case showFilter(SidebarFilter)
    /// Wechselt den Inhaltsbereich in den Monats-Kalender-Modus (eigener
    /// View-Modus, kein Sidebar-Filter). Optionaler Fokus-Tag bestimmt den Monat.
    case showCalendar(Date?)
}

extension Notification.Name {
    static let vmCommand = Notification.Name("vergissmeinnicht.command")
}

@main
struct VergissmeinnichtApp: App {
    @State private var container: AppContainer?
    @State private var initError: String?
    @State private var showShortcuts = false
    @State private var showSearchHelp = false
    @AppStorage(AppSettingsKey.hideCompleted) private var hideCompleted: Bool = false
    @AppStorage(AppSettingsKey.showDetailColumn) private var showDetailColumn: Bool = false

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
                    .sheet(isPresented: $showSearchHelp) {
                        SearchHelpView()
                    }
            } else {
                InitErrorView(message: initError ?? String(localized: "Unbekannter Fehler")) {
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
                Button("Suche-Hilfe") {
                    showSearchHelp = true
                }
                Divider()
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
            CommandMenu("Ansicht") {
                // Monats-Kalender als eigener Inhalts-Modus (#11). Brückt über den
                // bestehenden AppCommand/NotificationCenter-Pfad wie die "Berichte".
                Button("Kalender") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.showCalendar(nil))
                }
                .keyboardShortcut("k", modifiers: [.shift, .command])
                .disabled(container == nil)
                Divider()
                // Mail-Stil-Detailspalte (#33): Toggle spiegelt denselben
                // @AppStorage-Schlüssel wie der Toolbar-Button in der Hauptliste.
                Toggle("Detailspalte anzeigen", isOn: $showDetailColumn)
                    .keyboardShortcut("0", modifiers: [.option, .command])
                Toggle("Erledigte Aufgaben ausblenden", isOn: $hideCompleted)
                    .keyboardShortcut("h", modifiers: [.shift, .command])
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
            // Native Taskwarrior-Abhängigkeits-Reports. Vom User explizit als
            // Menüleisten-Zugang gewünscht (#3). Setzen den Sidebar-Filter über den
            // bestehenden AppCommand/NotificationCenter-Pfad.
            CommandMenu("Berichte") {
                Button("Blockiert") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.showFilter(.blocked))
                }
                .disabled(container == nil)
                Button("Blockierend") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.showFilter(.blocking))
                }
                .disabled(container == nil)
                Button("Nicht blockiert") {
                    NotificationCenter.default.post(name: .vmCommand, object: AppCommand.showFilter(.unblocked))
                }
                .disabled(container == nil)
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
