import ActivityKit
import Foundation
import UIKit

@MainActor
final class LiveActivityCoordinator {
    private var activity: Activity<LumaLexActivityAttributes>?
    private var lastEnglish = ""
    private var lastChinese = ""
    private var lastIsPlaying = false

    @discardableResult
    func update(title: String, english: String, chinese: String,
                elapsed: TimeInterval, isPlaying: Bool) -> Bool {
        guard UserDefaults.standard.bool(forKey: "lockScreenSubtitles"),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        guard activity != nil || isPlaying else { return false }
        let now = Date()
        guard activity == nil || english != lastEnglish || chinese != lastChinese ||
                isPlaying != lastIsPlaying else { return false }
        if activity == nil, UIApplication.shared.applicationState != .active { return false }
        lastEnglish = english
        lastChinese = chinese
        lastIsPlaying = isPlaying
        let state = LumaLexActivityAttributes.ContentState(
            english: String(english.prefix(500)), chinese: String(chinese.prefix(300)),
            elapsed: Int(elapsed), isPlaying: isPlaying
        )
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(90))
        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(attributes: .init(title: title), content: content)
        }
        return activity != nil
    }

    func end() {
        let previous = activity
        self.activity = nil
        lastEnglish = ""
        lastChinese = ""
        lastIsPlaying = false
        Task {
            await previous?.end(nil, dismissalPolicy: .immediate)
        }
    }
}
