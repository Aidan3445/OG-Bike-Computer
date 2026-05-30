//
//  CueEditorWaypointPin.swift
//  OG Bike Computer
//
//  Map pin for an imported or user-added waypoint while the Cue Editor is open.
//  Purple for imported POIs, blue for user-added; brighter and larger when
//  selected.
//

import SwiftUI

struct CueEditorWaypointPin: View {
    let isSelected: Bool
    let isUserAdded: Bool

    var body: some View {
        let size: CGFloat = isSelected ? 22 : 16
        let fill = (isUserAdded ? Color.blue : Color.purple).opacity(isSelected ? 1.0 : 0.85)
        let stroke = isSelected ? Color.white : Color.white.opacity(0.7)
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(stroke, lineWidth: isSelected ? 3 : 2))
                .shadow(radius: isSelected ? 4 : 1)
            Image(systemName: "flag.fill")
                .font(.system(size: isSelected ? 10 : 8, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
