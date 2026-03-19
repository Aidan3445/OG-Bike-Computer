//
//  GPXUUType.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import UniformTypeIdentifiers

extension UTType {
    static var gpx: UTType {
        UTType(importedAs: "com.topografix.gpx")
    }
}
