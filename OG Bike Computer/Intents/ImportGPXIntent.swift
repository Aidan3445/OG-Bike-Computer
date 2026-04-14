//
//  ImportGPXIntent.swift
//  OG Bike Computer
//
//  Import bridge: accepts a GPX file from the Share Sheet or the Shortcuts app,
//  parses it through RouteImportPipeline (the single ingestion point), and then
//  delegates to the existing SendRouteToWatchIntent so no watch-transfer logic
//  lives here.
//
//  Because this intent is UI-free (Shortcuts / automation), it does NOT show
//  RouteImportActionSheet.  That sheet is only displayed for interactive paths
//  (Share Sheet via onOpenURL, file picker in ContentView).
//

import AppIntents
import UniformTypeIdentifiers

struct ImportGPXIntent: AppIntent {
    static var title: LocalizedStringResource = "Import GPX Route"
    static var description = IntentDescription(
        "Import a GPX file and optionally send it to your watch or start a ride.",
        categoryName: "Route"
    )

    static var openAppWhenRun = true

    // Makes this intent appear in the Share Sheet for .gpx files
    static var supportedContentTypes: [UTType] = [.gpx]

    @Parameter(title: "GPX File")
    var file: IntentFile

    @Parameter(title: "Destination", default: .phoneOnly)
    var destination: RouteDestinationEnum

    @Parameter(title: "Activity Type", default: .cycling)
    var activityType: ActivityTypeEnum

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = file.data

        // Parse + save through the shared pipeline.
        // routeStore is nil here (intent process), so the pipeline falls back
        // to writing JSON directly to Documents/routes/.  RouteStore will pick
        // it up on next loadAll() when the app foregrounds (openAppWhenRun).
        let routes = await MainActor.run {
            RouteImportPipeline.shared.importGPX(data: data)
        }

        guard let route = routes.first else {
            return .result(dialog: "Could not import GPX file — no tracks found.")
        }

        let entity = await RouteEntity(id: route.id, name: route.name, distance: route.distance)

        switch destination {
        case .phoneOnly:
            return .result(dialog: "Route \"\(route.name)\" imported.")

        case .phoneAndWatch:
            let sendIntent = SendRouteToWatchIntent()
            sendIntent.route = entity
            sendIntent.destination = .phoneAndWatch
            sendIntent.activityType = activityType
            _ = try await sendIntent.perform()
            return .result(dialog: "Route \"\(route.name)\" sent to your watch.")

        case .phoneWatchStartRide:
            let sendIntent = SendRouteToWatchIntent()
            sendIntent.route = entity
            sendIntent.destination = .phoneWatchStartRide
            sendIntent.activityType = activityType
            _ = try await sendIntent.perform()
            return .result(dialog: "Route \"\(route.name)\" sent to your watch. Starting ride.")
        }
    }
}
