//
//  ServiceBadge.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import SwiftUI

struct ServiceBadge: View {
    let service: IntegrationServiceID

    var body: some View {
        Image(service.iconAsset)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
