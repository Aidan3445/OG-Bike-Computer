//
//  TipsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/15/26.
//

import Foundation

import SwiftUI

struct TipsView: View {
    var body: some View {
        List {
            NavigationLink {
                SettingsRecommendationView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch Settings")
                        Text(
                            "Keep watch app open before and during a ride."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.applewatch")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
