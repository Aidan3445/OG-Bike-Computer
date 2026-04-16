//
//  SettingsRecommendationView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/15/26.
//

import SwiftUI
import UIKit

struct SettingsRecommendationView: View {
    var onContinue: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            // Title
            Text("Recommended Settings")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("Keep Computa visible before and during your ride")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Image
            if let windowSize = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                Image("settingsRec")
                    .resizable()
                    .frame(width: windowSize.screen.bounds.width/2.5, height: windowSize.screen.bounds.height/2.5)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 30))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.secondary, lineWidth: 2)
                    }
                    .padding(.vertical, 4)
            } else {
                Image("settingsRec")
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.secondary, lineWidth: 2)
                    }
                    .padding(.vertical, 4)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 6) {
                Text("On your iPhone:")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Text("Watch App → General → Return to Clock → Computa")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Text("Set:")
                    .font(.subheadline)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("• Custom: After 2 minutes or 1 hour")
                    Text("• When in Session: Return to App")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Open Watch app button (best effort)
            Button {
                openWatchApp()
            } label: {
                Text("Open Watch Settings")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .padding(.top, 6)
            
            // Continue button (optional)
            if let onContinue {
                Button("Continue") {
                    onContinue()
                }
                .foregroundStyle(.accent)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    private func openWatchApp() {
        guard let url = URL(string: "itms-watchs://") else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
