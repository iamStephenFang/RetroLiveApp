import SwiftUI

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}

@main
struct RetroLiveImporterApp: App {
    var body: some Scene {
        WindowGroup {
            ImporterRootView()
        }
    }
}

private struct ImporterRootView: View {
    @AppStorage("retrolive.importer.onboarding.completedVersion")
    private var completedOnboardingVersion = 0

    var body: some View {
        Group {
            if completedOnboardingVersion >= ImporterOnboardingView.currentVersion {
                ContentView()
            } else {
                ImporterOnboardingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        completedOnboardingVersion = ImporterOnboardingView.currentVersion
                    }
                }
            }
        }
    }
}
