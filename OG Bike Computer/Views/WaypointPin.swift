//
//  WaypointPin.swift
//  OG Bike Computer
//
//  Marker rendered on the phone's route/ride detail maps for POIs/waypoints.
//

import SwiftUI

struct WaypointPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Image(systemName: "mappin")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.orange)
        }
    }
}
