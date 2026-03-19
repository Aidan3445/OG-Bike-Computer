//
//  MiniStat.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import SwiftUI

struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}
