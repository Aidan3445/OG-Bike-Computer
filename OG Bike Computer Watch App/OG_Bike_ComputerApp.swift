//
//  OG_Bike_ComputerApp.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI

@main
struct OG_Bike_Computer_Watch_AppApp: App {
    init() {
        ConnectivityManager.shared.activate()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
