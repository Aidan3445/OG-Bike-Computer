//
//  AlertContext.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation

struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
