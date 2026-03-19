//
//  GPXExporter.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import Foundation
import CoreLocation

struct GPXExporter {

    static func export(
        name: String,
        locations: [CLLocation],
        activityType: String = "cycling"
    ) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Computa" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(escapeXML(name))</name>
            <time>\(df.string(from: locations.first?.timestamp ?? Date()))</time>
          </metadata>
          <trk>
            <name>\(escapeXML(name))</name>
            <type>\(activityType)</type>
            <trkseg>\n
        """

        for loc in locations {
            xml += "      <trkpt lat=\"\(loc.coordinate.latitude)\" lon=\"\(loc.coordinate.longitude)\">"
            if loc.altitude != 0 {
                xml += "<ele>\(String(format: "%.1f", loc.altitude))</ele>"
            }
            xml += "<time>\(df.string(from: loc.timestamp))</time>"
            xml += "</trkpt>\n"
        }

        xml += """
            </trkseg>
          </trk>
        </gpx>
        """

        return xml
    }

    static func exportToFile(
        name: String,
        locations: [CLLocation],
        directory: URL,
        activityType: String = "cycling"
    ) -> String? {
        let gpxString = export(name: name, locations: locations, activityType: activityType)
        guard let data = gpxString.data(using: .utf8) else { return nil }

        let sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(sanitized)_\(Int(Date().timeIntervalSince1970)).gpx"
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("GPX write error: \(error)")
            return nil
        }
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
