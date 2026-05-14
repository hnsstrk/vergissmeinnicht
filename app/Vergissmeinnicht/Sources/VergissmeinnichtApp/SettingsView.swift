import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var serverUrl        = ""
    @State private var clientId         = ""
    @State private var encryptionSecret = ""
    @State private var statusMessage: String?
    @State private var showRestorePicker: Bool = false

    @AppStorage(AppSettingsKey.language)      private var language: String = AppLanguage.system.rawValue
    @AppStorage(AppSettingsKey.dueSoonDays)   private var dueSoonDays: Int = 7
    @AppStorage(AppSettingsKey.defaultFilter) private var defaultFilter: String = DefaultFilter.inbox.rawValue
    @AppStorage(AppSettingsKey.defaultSort)   private var defaultSort: String = SortOrder.id.rawValue
    @AppStorage(AppSettingsKey.notifications) private var notificationsEnabled: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            syncTab
                .tabItem { Label("Sync-Server", systemImage: "icloud") }
            maintenanceTab
                .tabItem { Label("Wartung", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 480)
        .onAppear { loadCredentials() }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section {
                Picker("Sprache", selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }
            } header: {
                Text("Sprache").font(.headline)
            } footer: {
                Text("Sprachwechsel wird nach App-Neustart wirksam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Beim Start zeigen", selection: $defaultFilter) {
                    ForEach(DefaultFilter.allCases) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                }
                Picker("Sortierung", selection: $defaultSort) {
                    ForEach(SortOrder.allCases) { s in
                        Text(s.label).tag(s.rawValue)
                    }
                }
            } header: {
                Text("Standardansicht").font(.headline)
            }

            Section {
                Toggle("Bei überfälligen Aufgaben benachrichtigen", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            Task { await NotificationService.shared.requestAuthorizationIfNeeded() }
                        }
                    }
            } header: {
                Text("Benachrichtigungen").font(.headline)
            } footer: {
                Text("Bei aktivierter Option zeigt die App nach dem Start eine Zusammenfassung der überfälligen Aufgaben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Stepper(value: $dueSoonDays, in: 1...60) {
                    Text("\(dueSoonDays) \(dueSoonDays == 1 ? "Tag" : "Tage")")
                }
            } header: {
                Text("Bald fällig").font(.headline)
            } footer: {
                Text("Tasks innerhalb dieses Fensters erscheinen unter „Bald fällig“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var syncTab: some View {
        Form {
            Section {
                TextField("Server-URL", text: $serverUrl)
                TextField("Client-ID", text: $clientId)
                SecureField("Encryption Secret", text: $encryptionSecret)
            } header: {
                Text("Sync-Server").font(.headline)
            }

            Section {
                HStack {
                    Button("Speichern") { saveCredentials() }
                        .buttonStyle(.borderedProminent)
                    Button("Test-Sync") {
                        Task { await runTestSync() }
                    }
                }
            }

            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var maintenanceTab: some View {
        Form {
            Section {
                HStack {
                    Button("Backup erstellen") {
                        Task { await runManualBackup() }
                    }
                    Button("Backups öffnen …") {
                        NSWorkspace.shared.open(backupsURL)
                    }
                    Button("Aus Backup wiederherstellen …") {
                        showRestorePicker = true
                    }
                }
            } header: {
                Text("Datensicherung").font(.headline)
            } footer: {
                Text("Vor jedem Sync wird automatisch ein Backup angelegt (rotierend, letzte 10 Stände werden behalten). Manuell kann jederzeit ein zusätzliches Backup erzeugt oder ein bestehendes Backup als aktive Replica eingespielt werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Legacy-Tasks reparieren") {
                    Task { await runRepair() }
                }
            } header: {
                Text("Wartung").font(.headline)
            } footer: {
                Text("Parst alte Descriptions mit +tag / project:foo / due:bar und schreibt sie als Properties zurück. Tasks mit bereits gesetzten Metadaten bleiben unangetastet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showRestorePicker) {
            BackupRestoreSheet(
                backupService: container.backupService,
                onRestored: {
                    statusMessage = "✓ Restore — App-Neustart empfohlen"
                }
            )
        }
    }

    private var backupsURL: URL {
        container.backupService.backupsURL
    }

    // MARK: - Private

    private func loadCredentials() {
        serverUrl        = KeychainStore.load(key: .serverUrl) ?? ""
        clientId         = KeychainStore.load(key: .clientId) ?? ""
        encryptionSecret = KeychainStore.load(key: .encryptionSecret) ?? ""
    }

    private func saveCredentials() {
        do {
            try KeychainStore.save(serverUrl,        for: .serverUrl)
            try KeychainStore.save(clientId,         for: .clientId)
            try KeychainStore.save(encryptionSecret, for: .encryptionSecret)
            statusMessage = "✓ Gespeichert"
        } catch {
            statusMessage = String(localized: "Fehler beim Speichern: \(error.localizedDescription)")
        }
    }

    private func runManualBackup() async {
        statusMessage = String(localized: "Sichere …")
        let service = container.backupService
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try service.createBackup(reason: "manual")
            }.value
            statusMessage = "✓ Backup: \(url.lastPathComponent)"
        } catch {
            statusMessage = String(localized: "Fehler: \(error.localizedDescription)")
        }
    }

    private func runRepair() async {
        statusMessage = String(localized: "Repariere …")
        let count = await container.repairLegacyTasks()
        if let err = container.lastError {
            statusMessage = String(localized: "Fehler: \(err)")
        } else {
            statusMessage = "✓ \(count) " + (count == 1 ? "Task repariert" : "Tasks repariert")
        }
    }

    private func runTestSync() async {
        statusMessage = String(localized: "Verbinde …")
        await container.sync(
            serverUrl:        serverUrl,
            clientId:         clientId,
            encryptionSecret: encryptionSecret
        )
        if let err = container.lastError {
            statusMessage = String(localized: "Fehler: \(err)")
        } else {
            statusMessage = "✓ Sync"
        }
    }
}
