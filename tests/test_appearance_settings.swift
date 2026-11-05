import SwiftUI
import AppKit
@main struct AppearanceSettingsTest {
    @MainActor static func main() {
        let suite = "org.pylab.tests.appearance." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var applications: [AppearanceMode] = []
        let settings = AppearanceSettings(defaults: defaults) { applications.append($0) }
        precondition(settings.mode == .system && applications == [.system])
        precondition(defaults.object(forKey: AppearanceSettings.preferenceKey) == nil)
        precondition(AppearanceMode.system.colorScheme == nil && AppearanceMode.system.nativeAppearance == nil)
        precondition(AppearanceMode.system.isDark(systemIsDark: true) && !AppearanceMode.system.isDark(systemIsDark: false))
        precondition(AppearanceMode.light.colorScheme == .light && AppearanceMode.dark.colorScheme == .dark)
        precondition(AppearanceMode.light.nativeAppearance?.name == .aqua && AppearanceMode.dark.nativeAppearance?.name == .darkAqua)
        settings.select(.system)
        precondition(applications == [.system], "Selecting current mode should not reapply it")
        settings.toggle(currentlyDark: false)
        precondition(settings.mode == .dark && applications == [.system, .dark])
        precondition(defaults.string(forKey: AppearanceSettings.preferenceKey) == "dark")
        settings.select(.dark)
        precondition(applications.count == 2, "Repeated explicit selection should be a no-op")
        // Explicit mode wins even if a caller's system appearance value is stale.
        settings.toggle(currentlyDark: false)
        precondition(settings.mode == .light && applications.last == .light)
        settings.toggle(currentlyDark: true)
        precondition(settings.mode == .dark && applications.last == .dark)
        var restoredApplications: [AppearanceMode] = []
        let restored = AppearanceSettings(defaults: defaults) { restoredApplications.append($0) }
        precondition(restored.mode == .dark && restoredApplications == [.dark])
        restored.select(.system)
        restored.toggle(currentlyDark: true)
        precondition(restored.mode == .light && restoredApplications == [.dark, .system, .light])
        precondition(defaults.string(forKey: AppearanceSettings.preferenceKey) == "light")
        let lightRestored = AppearanceSettings(defaults: defaults, applyAppearance: { _ in })
        precondition(lightRestored.mode == .light)
        defaults.set("unknown-future-mode", forKey: AppearanceSettings.preferenceKey)
        var fallbackApplications: [AppearanceMode] = []
        let fallback = AppearanceSettings(defaults: defaults) { fallbackApplications.append($0) }
        precondition(fallback.mode == .system && fallbackApplications == [.system])
        fallback.toggle(currentlyDark: false)
        precondition(fallback.mode == .dark && fallbackApplications == [.system, .dark])
        print("PASS: default System, persisted Light/Dark restore, invalid-value fallback, system-aware toggle, explicit-mode precedence and single-application/no-op callbacks")
    }
}
