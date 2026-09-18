import AppKit
import Foundation

@main
struct OnboardingProgressTests {
    @MainActor
    static func main() async {
        let domain = "com.cosmintrica.airfliq.setup-tests"
        precondition(Bundle.main.bundleIdentifier == domain)
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        _ = NSApplication.shared
        Permissions.hasRequestedFinderExtension = true
        Shortcut.hasConfigured = false

        let model = OnboardingExperienceModel()
        model.apply([.granted, .unknown, .unknown])
        precondition(model.activeIndex == 1 && model.completedStepCount == 1)
        model.apply([.granted, .granted, .unknown], celebrate: 1)
        precondition(model.celebratingIndex == 1)
        model.apply([.granted, .granted, .unknown])
        precondition(model.celebratingIndex == 1)
        try? await Task.sleep(for: .milliseconds(2250))
        precondition(model.activeIndex == 2 && model.celebratingIndex == nil)
        print("PASS: new grant advances once despite concurrent refresh")

        model.selectStep(1)
        model.apply([.granted, .granted, .unknown])
        precondition(model.activeIndex == 1)
        model.apply([.granted, .granted, .unknown], celebrate: 1)
        precondition(model.activeIndex == 2 && model.celebratingIndex == nil)
        print("PASS: cancel/refresh preserves step; confirmed existing access advances")

        model.selectStep(0)
        model.helpMode = .finderAccess
        model.performHelpAction()
        precondition(model.helpMode == nil && model.activeIndex == 2)
        print("PASS: finishing file-picker explanation advances")

        model.helpMode = .enableExtension
        model.apply([.granted, .granted, .granted], celebrate: 2)
        precondition(model.helpMode == nil)
        try? await Task.sleep(for: .milliseconds(2250))
        precondition(model.showShortcutStage && !model.showReadyStage)
        print("PASS: extension completion dismisses help and opens shortcut setup")
        model.stop()

        Shortcut.hasConfigured = true
        let configured = OnboardingExperienceModel()
        configured.apply([.granted, .granted, .denied])
        configured.helpMode = .enableExtension
        configured.apply([.granted, .granted, .granted])
        try? await Task.sleep(for: .milliseconds(2250))
        precondition(configured.showReadyStage && !configured.showShortcutStage)
        precondition(configured.completedStepCount == 4 && configured.helpMode == nil)
        print("PASS: background extension grant reaches ready with saved shortcut")
        configured.selectStep(2)
        configured.helpMode = .enableExtension
        configured.apply([.granted, .granted, .granted], celebrate: 2)
        precondition(configured.showReadyStage && configured.helpMode == nil)
        print("PASS: rechecking an enabled extension dismisses help and advances")
        configured.stop()

        let revoked = OnboardingExperienceModel()
        revoked.apply([.granted, .unknown, .unknown])
        revoked.apply([.granted, .granted, .unknown], celebrate: 1)
        revoked.apply([.granted, .denied, .unknown])
        try? await Task.sleep(for: .milliseconds(2250))
        precondition(revoked.activeIndex == 1 && !revoked.showReadyStage)
        print("PASS: revocation during celebration returns to the unresolved step")
        revoked.stop()
    }
}
