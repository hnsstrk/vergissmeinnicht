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
    static let showForecastStrip       = "showForecastStrip"        // Bool, Default true (Wochen-Streifen über der Liste)
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
