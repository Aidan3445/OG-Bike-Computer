//
//  GPXExporter.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import Foundation
import CoreLocation

struct GPXExporter {

    /// Per-point power/HR data for GPX extensions
    struct PointExtras {
        let power: Double?  // watts
        let heartRate: Double?  // bpm
    }

    /// One track segment for multi-segment exports.
    struct Segment {
        let name: String
        let locations: [CLLocation]
        let pointExtras: [PointExtras]?
    }

    /// Export multiple rides into a single GPX with one `<trkseg>` per segment.
    /// Each segment keeps its own real timestamps so a route reader can still see
    /// the gap between rides.
    static func exportMulti(
        name: String,
        segments: [Segment],
        activityType: String = "cycling"
    ) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let hasExtensions = segments.contains { seg in
            seg.pointExtras?.contains(where: { $0.power != nil || $0.heartRate != nil }) ?? false
        }
        let firstTime = segments.first?.locations.first?.timestamp ?? Date()

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Computa"
          xmlns="http://www.topografix.com/GPX/1/1"
        """
        if hasExtensions {
            xml += """

              xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
            """
        }
        xml += """
        >
          <metadata>
            <name>\(escapeXML(name))</name>
            <time>\(df.string(from: firstTime))</time>
          </metadata>
          <trk>
            <name>\(escapeXML(name))</name>
            <type>\(activityType)</type>\n
        """

        for seg in segments {
            xml += "    <trkseg>\n"
            xml += "      <!-- \(escapeXML(seg.name)) -->\n"
            for (i, loc) in seg.locations.enumerated() {
                xml += "      <trkpt lat=\"\(loc.coordinate.latitude)\" lon=\"\(loc.coordinate.longitude)\">"
                if loc.altitude != 0 {
                    xml += "<ele>\(String(format: "%.1f", loc.altitude))</ele>"
                }
                xml += "<time>\(df.string(from: loc.timestamp))</time>"
                if let extras = seg.pointExtras, i < extras.count {
                    let ext = extras[i]
                    if ext.power != nil || ext.heartRate != nil {
                        xml += "<extensions><gpxtpx:TrackPointExtension>"
                        if let hr = ext.heartRate {
                            xml += "<gpxtpx:hr>\(Int(hr.rounded()))</gpxtpx:hr>"
                        }
                        if let power = ext.power {
                            xml += "<gpxtpx:power>\(Int(power.rounded()))</gpxtpx:power>"
                        }
                        xml += "</gpxtpx:TrackPointExtension></extensions>"
                    }
                }
                xml += "</trkpt>\n"
            }
            xml += "    </trkseg>\n"
        }

        xml += """
          </trk>
        </gpx>
        """
        return xml
    }

    static func export(
        name: String,
        locations: [CLLocation],
        activityType: String = "cycling",
        pointExtras: [PointExtras]? = nil
    ) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let hasExtensions = pointExtras?.contains(where: { $0.power != nil || $0.heartRate != nil }) ?? false

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Computa"
          xmlns="http://www.topografix.com/GPX/1/1"
        """

        if hasExtensions {
            xml += """

              xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
            """
        }

        xml += """
        >
          <metadata>
            <name>\(escapeXML(name))</name>
            <time>\(df.string(from: locations.first?.timestamp ?? Date()))</time>
          </metadata>
          <trk>
            <name>\(escapeXML(name))</name>
            <type>\(activityType)</type>
            <trkseg>\n
        """

        for (i, loc) in locations.enumerated() {
            xml += "      <trkpt lat=\"\(loc.coordinate.latitude)\" lon=\"\(loc.coordinate.longitude)\">"
            if loc.altitude != 0 {
                xml += "<ele>\(String(format: "%.1f", loc.altitude))</ele>"
            }
            xml += "<time>\(df.string(from: loc.timestamp))</time>"

            if let extras = pointExtras, i < extras.count {
                let ext = extras[i]
                if ext.power != nil || ext.heartRate != nil {
                    xml += "<extensions><gpxtpx:TrackPointExtension>"
                    if let hr = ext.heartRate {
                        xml += "<gpxtpx:hr>\(Int(hr.rounded()))</gpxtpx:hr>"
                    }
                    if let power = ext.power {
                        xml += "<gpxtpx:power>\(Int(power.rounded()))</gpxtpx:power>"
                    }
                    xml += "</gpxtpx:TrackPointExtension></extensions>"
                }
            }

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
        activityType: String = "cycling",
        pointExtras: [PointExtras]? = nil
    ) -> String? {
        let gpxString = export(name: name, locations: locations, activityType: activityType, pointExtras: pointExtras)
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
