//
//  CueEditorHolder.swift
//  OG Bike Computer
//
//  Tiny wrapper that lets us @StateObject-park a Cue Editor view-model inside
//  RouteDetailView. The view-model itself can't be a direct @StateObject because
//  it needs a ProcessedRoute at construction time, which we only build lazily
//  when the user actually enters editor mode.
//

import Foundation
import Combine

@MainActor
final class CueEditorHolder: ObservableObject {
    @Published private(set) var viewModel: CueEditorViewModel?

    /// Forward the inner view-model's changes so RouteDetailView re-renders
    /// (map annotations, selection-driven zoom) whenever the editor updates.
    private var forwardSink: AnyCancellable?

    func ensure(for route: Route, routeStore: RouteStore) -> CueEditorViewModel {
        if let vm = viewModel, vm.route.id == route.id {
            return vm
        }
        let processed = RouteProcessor.process(route)
        let vm = CueEditorViewModel(route: route, processed: processed, routeStore: routeStore)
        viewModel = vm
        forwardSink = vm.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        return vm
    }

    func teardown() {
        forwardSink = nil
        viewModel = nil
    }
}
