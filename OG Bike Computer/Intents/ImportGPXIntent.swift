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
//  RouteImportActionSheet. Duplicates follow the action's own option instead.
//

import AppIntents
import UniformTypeIdentifiers

/// What the Import GPX Route action does when the file matches a saved route.
enum DuplicateHandlingEnum: String, AppEnum {
    case automatic
    case replace
    case keepBoth
    case useExisting
    case ask

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duplicate Handling")
    static var caseDisplayRepresentations: [DuplicateHandlingEnum: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(
            title: "Automatic", subtitle: "Replace updates, reuse identical, keep renamed copies"),
        .replace: "Replace",
        .keepBoth: "Keep Both",
        .useExisting: "Use Existing",
        .ask: DisplayRepresentation(title: "Ask", subtitle: "Only when a duplicate is found"),
    ]
}

enum ImportGPXError: Error, CustomLocalizedStringResourceConvertible {
    case noTracks

    var localizedStringResource: LocalizedStringResource {
        "No routes found in that GPX file."
    }
}

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

    @Parameter(title: "If It's a Duplicate", default: .automatic)
    var duplicates: DuplicateHandlingEnum

    static var parameterSummary: some ParameterSummary {
        When(\.$destination, .equalTo, .phoneWatchStartRide) {
            Summary(
                "Import \(\.$file) to \(\.$destination) as a \(\.$activityType) ride, if it's a duplicate \(\.$duplicates)"
            )
        } otherwise: {
            Summary("Import \(\.$file) to \(\.$destination), if it's a duplicate \(\.$duplicates)")
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<RouteEntity> & ProvidesDialog {
        let data = file.data
        let candidates = await MainActor.run {
            RouteImportPipeline.shared.importGPX(data: data)
        }
        guard let first = candidates.first else { throw ImportGPXError.noTracks }

        // Every track in the file follows the same option. The first one is
        // the route this action hands on.
        var resolved: [Route] = []
        var reusedFirst = false
        for candidate in candidates {
            guard let duplicate = candidate.duplicate else {
                resolved.append(candidate.route)
                continue
            }
            let choice = try await choice(for: duplicate, named: candidate.route.name)
            if candidate.id == first.id { reusedFirst = choice == .useExisting }
            let route = await MainActor.run {
                RouteImportPipeline.shared.resolve(candidate, as: choice)
            }
            resolved.append(route)
        }
        let route = resolved[0]
        let entity = RouteEntity(id: route.id, name: route.name, distance: route.distance)
        let imported =
            reusedFirst
            ? "\"\(route.name)\" was already imported." : "Route \"\(route.name)\" imported."

        switch destination {
        case .phoneOnly:
            return .result(value: entity, dialog: "\(imported)")

        case .phoneAndWatch:
            let sendIntent = SendRouteToWatchIntent()
            sendIntent.route = entity
            sendIntent.destination = .phoneAndWatch
            sendIntent.activityType = activityType
            _ = try await sendIntent.perform()
            return .result(value: entity, dialog: "\(imported) Sent to your watch.")

        case .phoneWatchStartRide:
            let sendIntent = SendRouteToWatchIntent()
            sendIntent.route = entity
            sendIntent.destination = .phoneWatchStartRide
            sendIntent.activityType = activityType
            _ = try await sendIntent.perform()
            return .result(value: entity, dialog: "\(imported) Sent to your watch. Starting ride.")
        }
    }

    private func choice(for duplicate: RouteDuplicate, named name: String) async throws
        -> RouteDuplicateChoice
    {
        switch duplicates {
        case .automatic: return duplicate.automaticChoice
        case .replace: return .replace
        case .keepBoth: return .keepBoth
        case .useExisting: return .useExisting
        case .ask:
            do {
                let picked = try await $duplicates.requestDisambiguation(
                    among: [.replace, .keepBoth, .useExisting],
                    dialog: "\(name): \(duplicate.explanation) What should Computa do?")
                switch picked {
                case .replace: return .replace
                case .keepBoth: return .keepBoth
                default: return .useExisting
                }
            } catch {
                // No one to ask, like an automation running in the background.
                return duplicate.automaticChoice
            }
        }
    }
}
