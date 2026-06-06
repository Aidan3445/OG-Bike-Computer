//
//  MapCameraState.swift
//  OG Bike Computer
//
//  Tiny ObservableObject that holds the live map camera heading. Owned by
//  RouteDetailView and observed directly by the few annotation views that
//  need to counter-rotate against the camera (HighlightChevron, MileMarkerLabel).
//  Keeping heading off the main view's @State means the Map's body — and
//  therefore every annotation, ForEach, and computed property in it — doesn't
//  re-render on every frame of a camera rotation, which was making zoomed-in
//  rotation feel laggy.
//

import Foundation
import Combine

@MainActor
final class MapCameraState: ObservableObject {
    @Published var heading: Double = 0
}
