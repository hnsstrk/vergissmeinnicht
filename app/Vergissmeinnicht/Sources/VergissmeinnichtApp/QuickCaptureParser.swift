import Foundation

/// Geparster Vorschau-Snapshot einer QuickCapture-Eingabe.
///
/// Description, Tags, Project und Due werden persistiert (siehe
/// `QuickCaptureSheet.save()` und `AppContainer.addTask(description:project:tags:due:)`).
/// Priority wird vom Parser erkannt, aber bislang nicht über die FFI gespeichert.
struct QuickCapturePreview: Equatable {
    var description: String
    var tags: [String]
    var project: String?
    var due: String?
    var priority: String?

    /// Es existiert mindestens ein erkanntes Metadaten-Token.
    var hasMetadata: Bool {
        !tags.isEmpty || project != nil || due != nil || priority != nil
    }
}

/// Parser für Taskwarrior-ähnliche QuickCapture-Eingaben.
///
/// Erkannt werden:
/// - `+tag` → in `tags` (ohne `+`)
/// - `project:value` → `project`
/// - `due:value` → `due`
/// - `priority:value` → `priority`
/// - `\\ ` (Backslash + Leerzeichen) innerhalb eines Tokens als literales Leerzeichen
///   in der Description (z.B. `meeting\\ notes +work` → description `"meeting notes"`)
///
/// Alle übrigen Tokens bilden in der Eingabe-Reihenfolge die `description`. Es findet
/// keine Validierung von Datums- oder Priority-Werten statt — das übernimmt die FFI,
/// sobald sie die Felder akzeptiert.
///
/// Karpathy 2 (Simplicity): bewusst weiterhin kein Quoting (`"…"`), kein
/// Mehrfach-Project, kein `#tag`/`!1`-Shortcut — Welle 4 persistiert ohnehin nur
/// die Description, und die Help-Note des Sheets nennt die unterstützte Syntax.
enum QuickCaptureParser {
    static func parse(_ input: String) -> QuickCapturePreview {
        var descriptionTokens: [String] = []
        var tags: [String] = []
        var project: String?
        var due: String?
        var priority: String?

        for token in tokenize(input) {
            if let value = stripPrefix("project:", from: token) {
                project = value
            } else if let value = stripPrefix("due:", from: token) {
                due = value
            } else if let value = stripPrefix("priority:", from: token) {
                priority = value
            } else if token.hasPrefix("+"), token.count > 1 {
                tags.append(String(token.dropFirst()))
            } else {
                descriptionTokens.append(token)
            }
        }

        return QuickCapturePreview(
            description: descriptionTokens.joined(separator: " "),
            tags: tags,
            project: project,
            due: due,
            priority: priority
        )
    }

    /// Splittet die Eingabe an Whitespace, behandelt aber `\\ ` (Backslash gefolgt von
    /// Leerzeichen) als literales Leerzeichen innerhalb des aktuellen Tokens. Andere
    /// Backslash-Sequenzen werden unverändert übernommen.
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var iterator = input.makeIterator()
        while let ch = iterator.next() {
            if ch == "\\" {
                if let next = iterator.next() {
                    if next == " " {
                        current.append(" ")
                    } else {
                        current.append(ch)
                        current.append(next)
                    }
                } else {
                    current.append(ch)
                }
            } else if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func stripPrefix(_ prefix: String, from token: String) -> String? {
        guard token.hasPrefix(prefix), token.count > prefix.count else { return nil }
        return String(token.dropFirst(prefix.count))
    }
}
