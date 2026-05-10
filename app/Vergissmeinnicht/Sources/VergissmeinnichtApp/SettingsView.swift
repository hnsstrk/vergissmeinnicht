import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var serverUrl        = ""
    @State private var clientId         = ""
    @State private var encryptionSecret = ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Sync-Server") {
                TextField("Server-URL", text: $serverUrl)
                TextField("Client-ID", text: $clientId)
                SecureField("Encryption Secret", text: $encryptionSecret)
            }

            HStack {
                Button("Speichern") { saveCredentials() }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Test-Sync") {
                    Task { await runTestSync() }
                }
            }
            .padding(.top, 4)

            if let msg = statusMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.secondary)
            }
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear { loadCredentials() }
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
            statusMessage = "Fehler beim Speichern: \(error)"
        }
    }

    private func runTestSync() async {
        statusMessage = "Verbinde …"
        await container.sync(
            serverUrl:        serverUrl,
            clientId:         clientId,
            encryptionSecret: encryptionSecret
        )
        if let err = container.lastError {
            statusMessage = "Fehler: \(err)"
        } else {
            statusMessage = "✓ Sync erfolgreich"
        }
    }
}
