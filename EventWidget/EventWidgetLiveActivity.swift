import ActivityKit
import WidgetKit
import SwiftUI

struct EventLiveActivityWidget: Widget {
    let kind: String = "EventLiveActivityWidget"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventLiveActivityAttributes.self) { context in
            
            EventLiveActivityView(
                eventName: context.attributes.eventName,
                eventLocation: context.attributes.eventLocation,
                eventStartTime: context.attributes.eventStartTime,
                eventEndTime: context.attributes.eventEndTime,
                statusEmoji: context.state.statusEmoji,
                isDynamicIsland: false
            )
            .padding()
            
            .activitySystemActionForegroundColor(Color.white)
            .activityBackgroundTint(Color.black)

        } dynamicIsland: { context in
           
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "clock.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.eventStartTime, style: .time)
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.eventName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EventLiveActivityView(
                        eventName: context.attributes.eventName,
                        eventLocation: context.attributes.eventLocation,
                        eventStartTime: context.attributes.eventStartTime,
                        eventEndTime: context.attributes.eventEndTime,
                        statusEmoji: context.state.statusEmoji,
                        isDynamicIsland: true
                    )
                }
            } compactLeading: {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .widgetURL(URL(string: "volunteeringopportunities://opportunity/\(context.attributes.opportunityId)"))
            .keylineTint(Color.indigo)
        }
    }
}

struct EventLiveActivityView: View {
    let eventName: String
    let eventLocation: String
    let eventStartTime: Date
    let eventEndTime: Date
    let statusEmoji: String
    let isDynamicIsland: Bool

    private var timeOnlyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        let timeRemaining = eventStartTime.timeIntervalSince(Date())
        let thirtyMinutes: TimeInterval = 30 * 60
        let eventHasStarted = timeRemaining <= 0

        VStack(alignment: .leading, spacing: isDynamicIsland ? 2 : 4) {
            if eventHasStarted {
                HStack(alignment: .bottom) {
                    Text("\(eventName) has started!")
                        .font(isDynamicIsland ? .subheadline : .headline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("\(eventStartTime, style: .time) to \(eventEndTime, style: .time)")
                        .font(isDynamicIsland ? .caption2 : .subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                Text("Location: \(eventLocation)")
                    .font(isDynamicIsland ? .caption : .subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .if(!isDynamicIsland) { view in
                        view.lineLimit(1)
                            .truncationMode(.tail)
                    }
            } else if timeRemaining <= thirtyMinutes {
                Text("\(eventName) starting soon at \(eventStartTime, formatter: timeOnlyFormatter).")
                    .font(isDynamicIsland ? .subheadline : .headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(eventLocation)
                    .font(isDynamicIsland ? .caption : .subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .if(!isDynamicIsland) { view in
                        view.lineLimit(1)
                            .truncationMode(.tail)
                    }
            } else {
                Text("\(eventName) is upcoming.")
                    .font(isDynamicIsland ? .subheadline : .headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                HStack {
                    Text(eventStartTime, style: .date)
                    Text(eventStartTime, style: .time)
                }
                .font(isDynamicIsland ? .caption : .subheadline)
                .foregroundColor(.white.opacity(0.8))
                Text(eventLocation)
                    .font(isDynamicIsland ? .caption : .subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .if(!isDynamicIsland) { view in
                        view.lineLimit(1)
                            .truncationMode(.tail)
                    }
            }
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

