import SwiftData
import SwiftUI

@main
struct LumaLexApp: App {
    @StateObject private var player = AudioPlayerService()

    init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "enabledBilingualLockScreenV5") {
            defaults.set(true, forKey: "lockScreenSubtitles")
            defaults.set(true, forKey: "enabledBilingualLockScreenV5")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(player)
        }
        .modelContainer(for: [
            UserProfile.self,
            AudioDocument.self,
            Transcript.self,
            SubtitleSegment.self,
            VocabularyItem.self,
            KnownExpression.self,
            ReviewRecord.self
        ])
    }
}
