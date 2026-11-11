//
//  LayoutProbe.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 10/28/26.
//

import Combine
import SwiftUI
import UIKit

extension View {
    /// Reports this screen's size and safe-area insets for the layout
    /// diagnostics. Does nothing in release builds. `corner` is where the
    /// overlay label sits, so the root's label stays clear of a screen's.
    func layoutProbe(_ name: String, corner: Alignment = .topLeading) -> some View {
        #if DEBUG
        modifier(LayoutProbeModifier(name: name, corner: corner))
        #else
        self
        #endif
    }
}

#if DEBUG

nonisolated struct LayoutReading: Equatable, Sendable {
    var size: CGSize
    var insets: EdgeInsets
}

/// Watches for the bug where a map screen acts as if the bottom of the
/// screen is halfway up. Logs one snapshot when it starts and one when it
/// clears, whether or not the overlay is showing.
final class LayoutProbeCenter: ObservableObject {
    static let shared = LayoutProbeCenter()

    @Published private(set) var keyboardHeight: CGFloat = 0
    private var readings: [String: LayoutReading] = [:]
    private var isAnomalous = false
    private var pendingStart: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                self?.setKeyboardHeight(max(0, Self.windowBounds.maxY - frame.minY))
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setKeyboardHeight(0) }
            .store(in: &cancellables)
    }

    func update(_ name: String, reading: LayoutReading?) {
        readings[name] = reading
        evaluate()
    }

    private func setKeyboardHeight(_ height: CGFloat) {
        guard height != keyboardHeight else { return }
        keyboardHeight = height
        evaluate()
    }

    /// A bottom inset over 100 pt or a screen under 70% of the window,
    /// both with the keyboard hidden.
    private func anomalyReason(for reading: LayoutReading) -> String? {
        guard keyboardHeight == 0 else { return nil }
        if reading.insets.bottom > 100 { return "bottomInset" }
        let windowHeight = Self.windowBounds.height
        if windowHeight > 0, reading.size.height < windowHeight * 0.7 { return "shortScreen" }
        return nil
    }

    private var anomalyReasons: [String] {
        readings.compactMap { name, reading in
            anomalyReason(for: reading).map { "\(name):\($0)" }
        }.sorted()
    }

    /// A screen's first layout pass can look broken for a few milliseconds,
    /// so an anomaly only counts once it has lasted a second.
    private func evaluate() {
        guard !anomalyReasons.isEmpty else {
            pendingStart?.cancel()
            pendingStart = nil
            if isAnomalous {
                isAnomalous = false
                DiagnosticsLog.event("Layout", "anomaly cleared | \(snapshot())")
            }
            return
        }
        guard !isAnomalous, pendingStart == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingStart = nil
            let reasons = anomalyReasons
            guard !reasons.isEmpty else { return }
            isAnomalous = true
            DiagnosticsLog.event("Layout", "anomaly started \(reasons.joined(separator: ",")) | \(snapshot())")
        }
        pendingStart = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
    }

    private func snapshot() -> String {
        let window = Self.keyWindow
        let bounds = window?.bounds ?? .zero
        let safe = window?.safeAreaInsets ?? .zero
        var parts = [
            "window=\(Int(bounds.width))x\(Int(bounds.height)) safe t=\(Int(safe.top)) b=\(Int(safe.bottom))",
            "keyboard=\(Int(keyboardHeight))",
            "presented=\(Self.topPresentedType(in: window))",
        ]
        for (name, r) in readings.sorted(by: { $0.key < $1.key }) {
            parts.append("\(name) \(Int(r.size.width))x\(Int(r.size.height)) t=\(Int(r.insets.top)) b=\(Int(r.insets.bottom))")
        }
        return parts.joined(separator: " | ")
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static var windowBounds: CGRect {
        keyWindow?.bounds ?? .zero
    }

    private static func topPresentedType(in window: UIWindow?) -> String {
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        guard let top, top !== window?.rootViewController else { return "none" }
        return String(describing: type(of: top))
    }
}

private struct LayoutProbeModifier: ViewModifier {
    let name: String
    let corner: Alignment
    @AppStorage("layoutOverlayEnabled") private var overlayEnabled = false
    @ObservedObject private var center = LayoutProbeCenter.shared
    @State private var reading: LayoutReading?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: LayoutReading.self) { proxy in
                LayoutReading(size: proxy.size, insets: proxy.safeAreaInsets)
            } action: { newReading in
                reading = newReading
                center.update(name, reading: newReading)
            }
            .onDisappear { center.update(name, reading: nil) }
            .overlay(alignment: corner) {
                if overlayEnabled, let reading {
                    LayoutProbeLabel(name: name, reading: reading, keyboardHeight: center.keyboardHeight)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct LayoutProbeLabel: View {
    let name: String
    let reading: LayoutReading
    let keyboardHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).bold()
            Text("\(Int(reading.size.width))×\(Int(reading.size.height))")
            Text("inset t \(Int(reading.insets.top)) b \(Int(reading.insets.bottom))")
            Text("kb \(Int(keyboardHeight))")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("Normal") {
    LayoutProbeLabel(
        name: "RideDetail",
        reading: LayoutReading(size: CGSize(width: 393, height: 852),
                               insets: EdgeInsets(top: 103, leading: 0, bottom: 83, trailing: 0)),
        keyboardHeight: 0)
        .padding()
}

#Preview("Stuck bottom inset") {
    LayoutProbeLabel(
        name: "RideDetail",
        reading: LayoutReading(size: CGSize(width: 393, height: 852),
                               insets: EdgeInsets(top: 103, leading: 0, bottom: 400, trailing: 0)),
        keyboardHeight: 0)
        .padding()
}

#Preview("Keyboard open") {
    LayoutProbeLabel(
        name: "RouteDetail",
        reading: LayoutReading(size: CGSize(width: 393, height: 852),
                               insets: EdgeInsets(top: 103, leading: 0, bottom: 336, trailing: 0)),
        keyboardHeight: 336)
        .padding()
}
#endif
