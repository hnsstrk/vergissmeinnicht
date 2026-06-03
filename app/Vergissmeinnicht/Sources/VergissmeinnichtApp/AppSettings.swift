import Foundation
import SwiftUI

/// Persistente App-Einstellungen über `UserDefaults`/`@AppStorage`.
///
/// Konstanten und Default-Werte zentral hier, damit Settings-View und konsumierende
/// Stellen (RootView, ViewModel, App-init) konsistent referenzieren.
enum AppSettingsKey {
    static let language       = "appLanguage"          // system | de | en
    static let dueSoonDays    = "dueSoonDays"          // Int, Default 7
    static let defaultFilter  = "defaultSidebarFilter" // raw String, Default "inbox"
    static let defaultSort    = "defaultSortOrder"     // raw String, Default "id"
    static let sortAscending  = "sortAscending"        // Bool, Default true
    static let notifications  = "notificationsEnabled" // Bool, Default false
    static let projectsExpanded = "sidebarProjectsExpanded" // Bool, Default true
    static let tagsExpanded     = "sidebarTagsExpanded"     // Bool, Default true
    static let hideCompleted    = "hideCompleted"           // Bool, Default false
    static let autoSyncMode          = "autoSyncMode"            // String (AutoSyncMode.rawValue), Default "manual"
    static let sidebarColoredIcons   = "sidebarColoredIcons"    // Bool, Default true
    static let savedSearches         = "savedSearches"          // JSON-String [SavedSearch], Default "[]"
    static let sidebarProjectHierarchy = "sidebarProjectHierarchy"   // Bool, Default true (hierarchische Projektdarstellung)
    static let sidebarCollapsedProjects = "sidebarCollapsedProjects" // JSON-String [String] eingeklappter Projekt-Pfade, Default "[]"
    static let forecastConfigs           = "forecastConfigs"          // JSON-Dictionary [ForecastPerspective.rawValue: ForecastConfig], Default "{}" (fehlende Perspektive → ForecastConfig.default(for:))
}

/// Darstellungsmodus der Vorschau über der Aufgabenliste (Follow-up zu #11):
/// aus, kompakter Wochen-Streifen oder tagesgruppierte Agenda (Things-Stil).
/// `.off` IST die Sichtbarkeitssteuerung — kein separater Schalter mehr.
enum ForecastDisplayMode: String, CaseIterable, Identifiable, Codable {
    case off, compact, agenda

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .off:     return "Aus"
        case .compact: return "Kompakt"
        case .agenda:  return "Agenda"
        }
    }
}

/// Sichtbares Zeitfenster der Vorschau ab heute. `days3` = 3 rollende Tage;
/// `weeks1` = 7 rollende Tage ab heute (entspricht dem alten `days7`); `weeks2/3/4`
/// reichen bis zum Ende der N-ten ISO-Woche (Montag-erste Woche, exklusiv).
enum ForecastRange: String, CaseIterable, Identifiable, Codable {
    case days3, weeks1, weeks2, weeks3, weeks4

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .days3:  return "Nächste 3 Tage"
        case .weeks1: return "1 Woche"
        case .weeks2: return "2 Wochen"
        case .weeks3: return "3 Wochen"
        case .weeks4: return "4 Wochen"
        }
    }

    /// Anzahl ISO-Wochen für die mehrwöchige Kompakt-Stapelung; `nil` für
    /// Tagesfenster (`days3`) und das rollende 1-Wochen-Fenster (`weeks1`), die
    /// als EINE Streifen-Zeile gerendert werden (Single-Week-Kompakt).
    var weekCount: Int? {
        switch self {
        case .days3, .weeks1: return nil
        case .weeks2:         return 2
        case .weeks3:         return 3
        case .weeks4:         return 4
        }
    }
}

/// Vorschau-Konfiguration EINER Perspektive (Follow-up #11): Darstellung, Zeitraum,
/// Tageskappung und KW-Anzeige. `display == .off` blendet die Vorschau dort aus
/// (keine separate Sichtbarkeits-Liste mehr). Codable → JSON-Dictionary in
/// `@AppStorage` (Schlüssel `ForecastPerspective.rawValue`).
struct ForecastConfig: Codable, Equatable {
    var display: ForecastDisplayMode
    var range: ForecastRange
    var maxPerDay: ForecastMaxPerDay
    var showCalendarWeeks: Bool

    /// Default je Perspektive: die vier nächst-relevanten Listen zeigen eine
    /// 1-Wochen-Agenda mit KW; alles andere (inkl. dynamischer Catch-all) ist aus.
    static func `default`(for perspective: ForecastPerspective) -> ForecastConfig {
        switch perspective {
        case .today, .todo, .dueSoon, .upcoming:
            return ForecastConfig(display: .agenda, range: .weeks1, maxPerDay: .five, showCalendarWeeks: true)
        case .inbox, .overdue, .waiting, .all, .dynamic:
            return ForecastConfig(display: .off, range: .weeks1, maxPerDay: .five, showCalendarWeeks: true)
        }
    }

    // MARK: - Persistenz (JSON-Dictionary, wie SavedSearch eine JSON-Liste ist)

    /// Löst die Konfiguration für `perspective` aus dem `@AppStorage`-Dictionary-
    /// String auf. Fehlt der Eintrag (oder ist der String korrupt), greift der
    /// perspektiven-spezifische Default.
    static func resolve(_ perspective: ForecastPerspective, from raw: String) -> ForecastConfig {
        decodeAll(from: raw)[perspective.rawValue] ?? .default(for: perspective)
    }

    /// Dekodiert das gesamte Dictionary; bei Fehler eine leere Map (→ Defaults).
    static func decodeAll(from raw: String) -> [String: ForecastConfig] {
        guard let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: ForecastConfig].self, from: data)
        else { return [:] }
        return map
    }

    /// Setzt die Konfiguration für eine Perspektive und gibt den neuen JSON-String
    /// zurück (Identität bei Encode-Fehler — kein stiller Datenverlust).
    static func update(
        _ perspective: ForecastPerspective,
        to config: ForecastConfig,
        in raw: String
    ) -> String {
        var map = decodeAll(from: raw)
        map[perspective.rawValue] = config
        guard let data = try? JSONEncoder().encode(map),
              let string = String(data: data, encoding: .utf8)
        else { return raw }
        return string
    }
}

/// Maximale Anzahl Aufgaben pro Tag in der Agenda, bevor ein „+N"-Hinweis greift.
enum ForecastMaxPerDay: String, CaseIterable, Identifiable, Codable {
    case three, five, all

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .three: return "3 pro Tag"
        case .five:  return "5 pro Tag"
        case .all:   return "Alle"
        }
    }

    /// Kappungswert; `nil` = keine Kappung.
    var cap: Int? {
        switch self {
        case .three: return 3
        case .five:  return 5
        case .all:   return nil
        }
    }
}

/// Sidebar-Perspektiven, die eine eigene Vorschau-Konfiguration tragen (Follow-up #11).
///
/// Die acht System-Zeilen sind je eine eigene Perspektive; die dynamischen
/// Perspektiven (Projekte, Tags, gespeicherte Suchen) teilen sich die Sammel-
/// Perspektive `dynamic`. Abhängigkeits-Berichte (`blocked`/`blocking`/`unblocked`)
/// sind bewusst NICHT abgebildet — `init?(for:)` liefert dort `nil`, sodass die
/// Vorschau dort nie zeigt.
enum ForecastPerspective: String, CaseIterable, Identifiable {
    // Reihenfolge folgt der Sidebar (allCases treibt die Settings-Liste):
    // Eingang zuerst, dann Heute/Zu erledigen/Überfällig/Bald fällig/Geplant/Wartend/Alle.
    case inbox, today, todo, overdue, dueSoon, upcoming, waiting, all
    /// Sammel-Schalter für Projekte / Tags / gespeicherte Suchen.
    case dynamic

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .today:    return "Heute"
        case .todo:     return "Zu erledigen"
        case .dueSoon:  return "Bald fällig"
        case .upcoming: return "Geplant"
        case .inbox:    return "Eingang"
        case .overdue:  return "Überfällig"
        case .waiting:  return "Wartend"
        case .all:      return "Alle"
        case .dynamic:  return "Projekte, Tags & gespeicherte Suchen"
        }
    }

    /// Klassifiziert einen aktiven `SidebarFilter` in eine Vorschau-Perspektive.
    /// Geschlossener Switch über alle 14 Fälle: der Compiler erzwingt die Zuordnung
    /// neuer Filter. `nil` für die drei Abhängigkeits-Berichte → Vorschau aus.
    init?(for filter: SidebarFilter) {
        switch filter {
        case .today:                          self = .today
        case .todo:                           self = .todo
        case .dueSoon:                        self = .dueSoon
        case .upcoming:                       self = .upcoming
        case .inbox:                          self = .inbox
        case .overdue:                        self = .overdue
        case .waiting:                        self = .waiting
        case .all:                            self = .all
        case .project, .tag, .savedSearch:    self = .dynamic
        case .blocked, .blocking, .unblocked: return nil
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, en
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .de:     return "Deutsch"
        case .en:     return "Englisch"
        }
    }

    /// Setzt `AppleLanguages` in `UserDefaults` entsprechend der Wahl. Wirkt erst
    /// beim nächsten App-Start — Apple hat keine Live-Locale-Umschaltung.
    static func applyAtLaunch() {
        let raw = UserDefaults.standard.string(forKey: AppSettingsKey.language) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: raw) ?? .system
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .de:
            UserDefaults.standard.set(["de"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }
}

/// Persistente Default-Sidebar-Auswahl. Speichert die `SidebarFilter`-Variante als
/// String; dynamische Filter (`.project(name)`, `.tag(name)`) werden bewusst nicht
/// persistiert — sie hängen vom Datenbestand ab.
enum DefaultFilter: String, CaseIterable, Identifiable {
    case all, today, todo, inbox, overdue, dueSoon, upcoming

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all:      return "Alle"
        case .today:    return "Heute"
        case .todo:     return "Zu erledigen"
        case .inbox:    return "Eingang"
        case .overdue:  return "Überfällig"
        case .dueSoon:  return "Bald fällig"
        case .upcoming: return "Geplant"
        }
    }

    var asSidebarFilter: SidebarFilter {
        switch self {
        case .all:      return .all
        case .today:    return .today
        case .todo:     return .todo
        case .inbox:    return .inbox
        case .overdue:  return .overdue
        case .dueSoon:  return .dueSoon
        case .upcoming: return .upcoming
        }
    }
}

/// Auto-Sync-Modus: wie häufig soll die App automatisch synchronisieren.
enum AutoSyncMode: String, CaseIterable, Identifiable {
    case manual, m5, m15, m60, immediate

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .manual:    return "Nur manuell"
        case .m5:        return "Alle 5 Minuten"
        case .m15:       return "Alle 15 Minuten"
        case .m60:       return "Alle 60 Minuten"
        case .immediate: return "Bei jeder Änderung"
        }
    }

    /// Intervall in Sekunden. `nil` für Modi ohne Timer (manual, immediate).
    var interval: TimeInterval? {
        switch self {
        case .manual:    return nil
        case .m5:        return 5 * 60
        case .m15:       return 15 * 60
        case .m60:       return 60 * 60
        case .immediate: return nil
        }
    }
}
