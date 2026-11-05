import SwiftUI
import AppKit

/// One preference controls all windows, native panels, and the Python editor.
enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Use macOS Appearance"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    static let preferenceKey = "appearance.mode.v1"
    @Published private(set) var mode: AppearanceMode
    private let defaults: UserDefaults
    private let applyAppearance: @MainActor (AppearanceMode) -> Void

    init(defaults: UserDefaults = .standard,
         applyAppearance: (@MainActor (AppearanceMode) -> Void)? = nil) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.preferenceKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        self.applyAppearance = applyAppearance ?? { mode in
            // AppKit controls, title bars, sheets, alerts, and file panels all
            // follow this app-only override; macOS's own setting is untouched.
            NSApplication.shared.appearance = mode.nativeAppearance
        }
        self.applyAppearance(mode)
    }

    func select(_ mode: AppearanceMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.preferenceKey)
        applyAppearance(mode)
    }

    func toggle(currentlyDark: Bool) {
        select(mode.isDark(systemIsDark: currentlyDark) ? .light : .dark)
    }
}

struct AppearanceModePicker: View {
    @ObservedObject var settings: AppearanceSettings
    var body: some View {
        Picker("Appearance", selection: Binding(get: { settings.mode }, set: { settings.select($0) })) {
            ForEach(AppearanceMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbol).tag(mode)
            }
        }.accessibilityLabel("App appearance")
    }
}

struct AppearanceMenu: View {
    @ObservedObject var settings: AppearanceSettings
    var body: some View {
        Menu { AppearanceModePicker(settings: settings) } label: {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
        }
    }
}

struct AppearanceCommands: Commands {
    @ObservedObject var settings: AppearanceSettings
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            AppearanceMenu(settings: settings)
        }
    }
}
