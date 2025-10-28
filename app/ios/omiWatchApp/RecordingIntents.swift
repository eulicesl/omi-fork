import AppIntents
import SwiftUI

// MARK: - Start Recording Intent
@available(watchOS 9.0, iOS 16.0, *)
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start recording audio on your Omi Watch")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // This will open the app and trigger recording
        // The actual recording start will be handled by the app when it opens
        return .result()
    }
}

// MARK: - App Shortcuts Provider
@available(watchOS 9.0, iOS 16.0, *)
struct OmiWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "Record with \(.applicationName)",
                "Begin recording on \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
    }
}
