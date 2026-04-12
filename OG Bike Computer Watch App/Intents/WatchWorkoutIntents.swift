//
//  WatchWorkoutIntents.swift
//  OG Bike Computer Watch App
//
//  Implements StartWorkoutIntent, PauseWorkoutIntent, and ResumeWorkoutIntent
//  protocols so the app appears in the Apple Watch Ultra Action Button settings
//  and can be controlled via the Action Button during a workout.
//

#if os(watchOS)
import AppIntents

// MARK: - Workout Style Enum

enum WorkoutStyleEnum: String, AppEnum {
    case cycling
    case running
    case walking
    case hiking

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout Style")

    static var caseDisplayRepresentations: [WorkoutStyleEnum: DisplayRepresentation] = [
        .cycling: DisplayRepresentation(title: "Cycling", image: .init(systemName: "bicycle")),
        .running: DisplayRepresentation(title: "Running", image: .init(systemName: "figure.run")),
        .walking: DisplayRepresentation(title: "Walking", image: .init(systemName: "figure.walk")),
        .hiking: DisplayRepresentation(title: "Hiking", image: .init(systemName: "figure.hiking"))
    ]

    var activityType: ActivityType {
        switch self {
        case .cycling: return .cycling
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        }
    }
}

// MARK: - Start Workout (Action Button)

struct WatchStartWorkoutIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource = "Start Ride"
    static var openAppWhenRun: Bool { true }

    static var suggestedWorkouts: [WatchStartWorkoutIntent] {
        [
            WatchStartWorkoutIntent(.cycling),
            WatchStartWorkoutIntent(.running),
            WatchStartWorkoutIntent(.walking),
            WatchStartWorkoutIntent(.hiking)
        ]
    }

    @Parameter(title: "Workout Style")
    var workoutStyle: WorkoutStyleEnum

    init() {
        workoutStyle = .cycling
    }

    init(_ style: WorkoutStyleEnum) {
        workoutStyle = style
    }

    var displayRepresentation: DisplayRepresentation {
        WorkoutStyleEnum.caseDisplayRepresentations[workoutStyle]
            ?? DisplayRepresentation(title: "Start Ride")
    }

    var localizedStringResource: LocalizedStringResource {
        switch workoutStyle {
        case .cycling: return "Start Cycling"
        case .running: return "Start Running"
        case .walking: return "Start Walking"
        case .hiking: return "Start Hiking"
        }
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .actionButtonStartRide,
                object: workoutStyle.activityType
            )
        }
        return .result()
    }
}

// MARK: - Pause Workout (Action Button during ride)

struct WatchPauseWorkoutIntent: PauseWorkoutIntent {
    static var title: LocalizedStringResource = "Pause Ride"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .actionButtonPauseRide,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - Resume Workout (Action Button during ride)

struct WatchResumeWorkoutIntent: ResumeWorkoutIntent {
    static var title: LocalizedStringResource = "Resume Ride"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .actionButtonResumeRide,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let actionButtonStartRide = Notification.Name("actionButtonStartRide")
    static let actionButtonPauseRide = Notification.Name("actionButtonPauseRide")
    static let actionButtonResumeRide = Notification.Name("actionButtonResumeRide")
}
#endif
