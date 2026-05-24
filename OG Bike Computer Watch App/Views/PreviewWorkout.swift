//
//  PreviewWorkout.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/20/26.
//


import SwiftUI

// Minimal stub — replace with your real WorkoutManager if you want live state
@Observable
final class PreviewWorkout {
    var isPaused: Bool = false
    var isAutoPaused: Bool = false
    func pause()  { isPaused = true }
    func resume() { isPaused = false }
}

// Wraps just the overlay so you can preview it in isolation
private struct ControlsOverlayPreviewContainer: View {
    var workout: PreviewWorkout
    @State var page: Int = 1
    @State var voiceEnabled: Bool = true
    @State var endCountdown: Double = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        controlsOverlay
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
    }
        

    // Paste your real controlsOverlay computed property here, or reference it
    // from your actual view file if it's accessible. Stubbed inline for isolation:
    private var controlsOverlay: some View {
        VStack(spacing: 12) {
            Text(workout.isPaused || workout.isAutoPaused ? "Paused" : "Riding")
                .font(.headline)
                .foregroundStyle(workout.isAutoPaused || workout.isPaused ? .yellow : .green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top,16)
                if workout.isPaused || workout.isAutoPaused {
                    Button {
                        cancelEndCountdown()
                        workout.resume()
                        withAnimation { page = 2 }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                } else {
                    Button {
                        cancelEndCountdown()
                        workout.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Color(red: 0.62, green: 0.38, blue: 0.93))
                }
                ZStack {
                    if endCountdown > 0 {
                        Button { cancelEndCountdown() } label: {
                            ZStack {
                                Circle()
                                    .trim(from: 0, to: endCountdown / 3.0)
                                    .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 36, height: 36)
                                Text(String(Int(ceil(3.0 - endCountdown))))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(role: .destructive) { startEndCountdown() } label: {
                            Label("End Ride", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 44)
                Divider()
                Toggle(isOn: $voiceEnabled) {
                    Label("Voice", systemImage: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.caption)
                }
                .onChange(of: voiceEnabled) { _, newValue in
                    VoiceNavigator.shared.isEnabled = newValue
                }
            
        }
        .ignoresSafeArea(edges: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if endCountdown > 0 { cancelEndCountdown() }
        }
        .onChange(of: page) { _, _ in cancelEndCountdown() }
    }

    func startEndCountdown() {
        endCountdown = 0.01
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            endCountdown += 0.05
            if endCountdown >= 3.0 {
                countdownTimer?.invalidate()
                endCountdown = 0
                // In real code this would end the workout
            }
        }
    }

    func cancelEndCountdown() {
        countdownTimer?.invalidate()
        endCountdown = 0
    }
}

#Preview("Riding") {
    ControlsOverlayPreviewContainer(workout: PreviewWorkout())
}

#Preview("Paused") {
    let w = PreviewWorkout()
    w.isPaused = true
    return ControlsOverlayPreviewContainer(workout: w)
}

#Preview("Auto-Paused") {
    let w = PreviewWorkout()
    w.isAutoPaused = true
    return ControlsOverlayPreviewContainer(workout: w)
}

#Preview("End Countdown") {
    ControlsOverlayPreviewContainer(workout: PreviewWorkout(), endCountdown: 1.5)
}
