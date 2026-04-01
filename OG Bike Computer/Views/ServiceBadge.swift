//
//  ServiceBadge.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import SwiftUI

struct ServiceBadge: View {
    let service: IntegrationServiceID

    var body: some View {
        Image(systemName: service.iconName)
            .font(.caption2)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch service {
        case .rideWithGPS: return .orange
        case .strava: return .orange
        }
    }
}
