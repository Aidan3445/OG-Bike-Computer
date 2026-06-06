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

    /// Forward only the inner view-model's structural changes (edits,
    /// selection, placement mode) to RouteDetailView. Draft / form-field
    /// publishes are NOT forwarded so per-keystroke typing in the panel
    /// doesn't re-render the map and its expensive annotations.
    private var forwardSinks: Set<AnyCancellable> = []

    func ensure(for route: Route, routeStore: RouteStore) -> CueEditorViewModel {
        if let vm = viewModel, vm.route.id == route.id {
            return vm
        }
        let processed = RouteProcessor.process(route)
        let vm = CueEditorViewModel(route: route, processed: processed, routeStore: routeStore)
        viewModel = vm

        forwardSinks.removeAll()
        // Build a publisher that fires on every meaningful change but ignores
        // draft/form-field churn. dropFirst() suppresses the initial value.
        let signals: [AnyPublisher<Void, Never>] = [
            vm.$edits.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            vm.$selection.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            vm.$waypointSelection.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            vm.$placementMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            vm.$isComposingEdit.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            vm.$isComposingAdd.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            vm.$isComposingWaypoint.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(signals)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &forwardSinks)

        return vm
    }

    func teardown() {
        forwardSinks.removeAll()
        viewModel = nil
    }
}
