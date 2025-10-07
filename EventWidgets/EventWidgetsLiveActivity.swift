//
//  EventWidgetsLiveActivity.swift
//  EventWidgets
//
//  Created by Chey K on 5/10/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct EventWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct EventWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension EventWidgetsAttributes {
    fileprivate static var preview: EventWidgetsAttributes {
        EventWidgetsAttributes(name: "World")
    }
}

extension EventWidgetsAttributes.ContentState {
    fileprivate static var smiley: EventWidgetsAttributes.ContentState {
        EventWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: EventWidgetsAttributes.ContentState {
         EventWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: EventWidgetsAttributes.preview) {
   EventWidgetsLiveActivity()
} contentStates: {
    EventWidgetsAttributes.ContentState.smiley
    EventWidgetsAttributes.ContentState.starEyes
}
