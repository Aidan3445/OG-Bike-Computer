//
//  GetHeldRideIntent.swift
//  OG Bike Computer
//
//  Tells a shortcut whether a ride is on hold, e.g. to continue it if there
//  is one and start a new ride if not.
//

// Phone only: held rides are read from the phone's ride store.
#if os(iOS) && !WIDGET_EXTENSION
import AppIntents
import Foundation

struct GetHeldRideIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Held Ride"
    static var description: IntentDescription = "Returns whether a ride is on hold, and says which one."

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        guard let held = loadHeldRide() else {
            return .result(value: false, dialog: "No ride is on hold.")
        }
        let distance = await MainActor.run {
            UnitState.shared.preferences = UserSettingsStore.shared.settings.unitPreferences
            return formatDistance(held.distance)
        }
        let heldAt = held.date.addingTimeInterval(held.elapsedTime)
            .formatted(date: .abbreviated, time: .shortened)
        return .result(value: true, dialog: "\(held.name) is on hold at \(distance), held \(heldAt).")
    }
}
#endif
