import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct LumaLexWidgetBundle: WidgetBundle {
    var body: some Widget { LumaLexLiveActivity() }
}

private struct LumaLexLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LumaLexActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.english).font(.subheadline).lineLimit(3)
                if !context.state.chinese.isEmpty {
                    Text(context.state.chinese).font(.subheadline).lineLimit(3)
                }
                Divider()
                HStack {
                    Text(context.attributes.title).lineLimit(1)
                    Spacer()
                    Text(String(format: "%d:%02d", context.state.elapsed / 60,
                                context.state.elapsed % 60))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.english).font(.headline).lineLimit(2)
                        if !context.state.chinese.isEmpty {
                            Text(context.state.chinese).font(.caption).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title).font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }
}
