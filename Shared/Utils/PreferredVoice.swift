//
//  PreferredVoice.swift
//  OG Bike Computer
//
//  Resolves the highest-quality available AVSpeechSynthesisVoice for en-US.
//  Premium and enhanced voices must be downloaded by the user via
//  Settings → Accessibility → Spoken Content → Voices. The system returns
//  nil when a voice isn't installed; we walk the preferred list until
//  something resolves and otherwise pick the best available en-US voice.
//

import AVFoundation

enum PreferredVoice {
    /// Hand-picked en-US voices, premium first then enhanced. Order is the
    /// fallback chain — each is tried in turn and the first installed one wins.
    private static let preferredIdentifiers: [String] = [
        "com.apple.voice.premium.en-US.Ava",
        "com.apple.voice.premium.en-US.Evan",
        "com.apple.voice.premium.en-US.Zoe",
        "com.apple.voice.premium.en-US.Joelle",
        "com.apple.voice.premium.en-US.Allison",
        "com.apple.voice.enhanced.en-US.Ava",
        "com.apple.voice.enhanced.en-US.Evan",
        "com.apple.voice.enhanced.en-US.Zoe",
        "com.apple.voice.enhanced.en-US.Allison"
    ]

    /// Best installed en-US voice. Computed each call (the lookups are cheap
    /// and the user can install voices at runtime, so we don't cache).
    static var resolved: AVSpeechSynthesisVoice {
        for id in preferredIdentifiers {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }
        // No premium/enhanced voice installed — fall back to the highest-quality
        // en-US voice the system reports as available.
        if let best = AVSpeechSynthesisVoice.speechVoices()
            .filter({ $0.language == "en-US" })
            .max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return best
        }
        // Last-ditch: any en-US voice. Force-unwrap is safe — iOS/watchOS
        // always ship at least one en-US compact voice.
        return AVSpeechSynthesisVoice(language: "en-US")!
    }

    /// True if the resolved voice is enhanced or premium quality. Useful for
    /// surfacing a "you can install nicer voices" hint when only the compact
    /// default is available.
    static var hasUpgradedVoice: Bool {
        resolved.quality.rawValue > AVSpeechSynthesisVoiceQuality.default.rawValue
    }
}
