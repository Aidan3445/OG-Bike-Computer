//
//  WorkoutTabOrder.swift
//  OG Bike Computer
//
//  Resolves the user's stored tab order against the live route/elevation/page
//  state, dropping invalid entries and appending anything new at the end.
//

import Foundation

enum WorkoutTabOrder {
    /// Build the final ordered list of tabs to render.
    ///
    /// - hasRoute: true if a route is loaded (controls whether elevation appears)
    /// - elevationEnabled: user's setting for showing the elevation screen
    /// - pages: current MetricPage list
    /// - stored: the user's saved order; nil means "use the default"
    static func resolve(
        hasRoute: Bool,
        elevationEnabled: Bool,
        pages: [MetricPage],
        stored: [WorkoutTabKey]?
    ) -> [WorkoutTabKey] {
        let availableMetrics = pages.map { WorkoutTabKey.metricPage($0.id) }
        let showElevation = hasRoute && elevationEnabled

        // Default order: route map, elevation (if shown), then metric pages.
        let defaultOrder: [WorkoutTabKey] = {
            var keys: [WorkoutTabKey] = [.routeMap]
            if showElevation { keys.append(.elevation) }
            keys.append(contentsOf: availableMetrics)
            return keys
        }()

        guard let stored = stored, !stored.isEmpty else { return defaultOrder }

        // Filter stored entries to those still valid right now.
        var ordered: [WorkoutTabKey] = stored.filter { key in
            switch key.kind {
            case .routeMap:    return true
            case .elevation:   return showElevation
            case .metricPage:  return availableMetrics.contains { $0.id == key.id }
            }
        }

        // Always make sure the route map is present (it's the entry point).
        if !ordered.contains(where: { $0.kind == .routeMap }) {
            ordered.insert(.routeMap, at: 0)
        }
        if showElevation && !ordered.contains(where: { $0.kind == .elevation }) {
            // Place elevation right after route map by default
            if let routeIdx = ordered.firstIndex(where: { $0.kind == .routeMap }) {
                ordered.insert(.elevation, at: ordered.index(after: routeIdx))
            } else {
                ordered.append(.elevation)
            }
        }

        // Append any newly-added metric pages we don't have stored yet.
        for metric in availableMetrics where !ordered.contains(where: { $0.id == metric.id }) {
            ordered.append(metric)
        }

        return ordered
    }
}
