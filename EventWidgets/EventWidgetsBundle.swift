//
//  EventWidgetsBundle.swift
//  EventWidgets
//
//  Created by Chey K on 5/10/25.
//

import WidgetKit
import SwiftUI

@main
struct EventWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EventWidgets()
        EventWidgetsControl()
        EventWidgetsLiveActivity()
    }
}
