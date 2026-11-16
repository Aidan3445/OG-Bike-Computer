//
//  TurnHaptics.swift
//  OG Bike Computer Watch App
//

import WatchKit

/// Wrist taps for turn alerts, when the rider's alert settings include haptics.
enum TurnHaptics {
    static func play(for alert: NavigationTracker.TurnAlert, preferences: NavigationAlertPreferences) {
        let intensity = preferences.haptics.intensity
        switch alert {
        case .warning:
            guard preferences.turnAlerts.resolvedPrimaryApproachMode().includesHaptic else { return }
            play(.click, intensity: intensity)
        case .imminent(let turn):
            guard preferences.turnAlerts.resolvedAtTurnMode().includesHaptic else { return }
            play(haptic(for: turn.direction), intensity: intensity)
        }
    }

    private static func haptic(for direction: TurnDirection) -> WKHapticType {
        switch direction {
        case .left, .slightLeft, .sharpLeft: return .directionDown
        case .right, .slightRight, .sharpRight: return .directionUp
        case .uTurn: return .failure
        case .straight: return .success
        }
    }

    /// Light always clicks. Strong plays the tap twice.
    private static func play(_ type: WKHapticType, intensity: HapticIntensity) {
        let device = WKInterfaceDevice.current()
        switch intensity {
        case .light:
            device.play(.click)
        case .medium:
            device.play(type)
        case .strong:
            device.play(type)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                device.play(type)
            }
        }
    }
}
