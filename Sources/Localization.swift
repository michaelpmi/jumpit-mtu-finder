import Foundation

/// Selectable UI languages. rawValue == .lproj folder / locale code ("system" = follow macOS).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, en, es, ca, fr, it
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return "System"
        case .de:     return "Deutsch"
        case .en:     return "English"
        case .es:     return "Español"
        case .ca:     return "Català"
        case .fr:     return "Français"
        case .it:     return "Italiano"
        }
    }
}

/// Global language state + string lookup. `override == nil` follows the system language.
/// Mutating `override` before a SwiftUI re-render makes every `L(...)` return fresh strings.
/// Access is lock-guarded so a stray lookup off the main thread can't data-race.
enum Lang {
    static let storageKey = "appLanguage"

    private static let lock = NSLock()
    private static var _override: String?

    static var override: String? {
        get { lock.lock(); defer { lock.unlock() }; return _override }
        set { lock.lock(); defer { lock.unlock() }; _override = newValue }
    }

    /// Apply a persisted/selected raw value; anything unknown falls back to system.
    static func apply(_ raw: String) {
        let lang = AppLanguage(rawValue: raw) ?? .system
        override = (lang == .system) ? nil : lang.rawValue
    }

    static func bundle() -> Bundle {
        if let code = override,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return Bundle.main
    }

    static func string(_ key: String) -> String {
        bundle().localizedString(forKey: key, value: key, table: nil)
    }
}

/// Localize `key`, optionally formatting with `args` (supports positional %1$@ / %2$lld specifiers).
func L(_ key: String, _ args: CVarArg...) -> String {
    let fmt = Lang.string(key)
    return args.isEmpty ? fmt : String(format: fmt, arguments: args)
}
