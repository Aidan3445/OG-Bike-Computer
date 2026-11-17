//
//  GPXExporter.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import CoreLocation
import Foundation
import os

nonisolated private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "GPXExporter")

nonisolated struct GPXExporter {

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
                xml +=
                    "      <trkpt lat=\"\(loc.coordinate.latitude)\" lon=\"\(loc.coordinate.longitude)\">"
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

        let hasExtensions =
            pointExtras?.contains(where: { $0.power != nil || $0.heartRate != nil }) ?? false

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
            xml +=
                "      <trkpt lat=\"\(loc.coordinate.latitude)\" lon=\"\(loc.coordinate.longitude)\">"
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

    /// Route GPX with its cues and POIs as waypoints ahead of the track, after
    /// the Cue Editor's changes, so the file matches what the watch rides.
    /// Turn cues are named by direction and POIs are typed "poi", which is
    /// how our importer tells them apart, so the file imports back the same.
    static func exportRoute(_ route: Route) -> String {
        let processed = RouteProcessor.process(route)
        let cues = processed.turnPoints(for: .provided)
        let pois = processed.resolvedPOIs(importedWaypoints: route.waypoints ?? [])

        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="Computa"
              xmlns="http://www.topografix.com/GPX/1/1">
              <metadata>
                <name>\(escapeXML(route.name))</name>
              </metadata>\n
            """

        for cue in cues {
            xml += "  <wpt lat=\"\(cue.coordinate.latitude)\" lon=\"\(cue.coordinate.longitude)\">"
            xml += "<name>\(escapeXML(cue.direction.label))</name>"
            if let desc = cue.description, !desc.isEmpty {
                xml += "<desc>\(escapeXML(desc))</desc>"
            }
            xml += "</wpt>\n"
        }
        for poi in pois {
            xml += "  <wpt lat=\"\(poi.coordinate.latitude)\" lon=\"\(poi.coordinate.longitude)\">"
            xml += "<name>\(escapeXML(poi.name))</name>"
            if let desc = poi.description, !desc.isEmpty {
                xml += "<desc>\(escapeXML(desc))</desc>"
            }
            xml += "<type>poi</type></wpt>\n"
        }

        xml += "  <trk>\n    <name>\(escapeXML(route.name))</name>\n    <trkseg>\n"
        for pt in route.points {
            xml += "      <trkpt lat=\"\(pt.lat)\" lon=\"\(pt.lon)\">"
            if let ele = pt.elevation {
                xml += "<ele>\(String(format: "%.1f", ele))</ele>"
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

    /// Writes the files into a folder and zips it into the temp directory as
    /// `<folderName>.zip`. Repeated names get `_2`, `_3` and so on. Disk
    /// bound, so call it off the main thread.
    static func zip(_ files: [(name: String, data: Data)], folderName: String) -> URL? {
        guard !files.isEmpty else { return nil }
        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? fm.removeItem(at: stagingDir)
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        } catch {
            logger.log("zip staging dir error: \(error.localizedDescription)")
            return nil
        }
        defer { try? fm.removeItem(at: stagingDir) }

        var usedNames: Set<String> = []
        var wrote = 0
        for file in files {
            var fileName = file.name
            var dedupe = 2
            while usedNames.contains(fileName) {
                fileName = file.name.replacingOccurrences(of: ".gpx", with: "_\(dedupe).gpx")
                dedupe += 1
            }
            usedNames.insert(fileName)
            do {
                try file.data.write(to: stagingDir.appendingPathComponent(fileName))
                wrote += 1
            } catch {
                logger.log("zip write error for \(fileName): \(error.localizedDescription)")
            }
        }
        guard wrote > 0 else { return nil }

        // NSFileCoordinator's zip is only valid inside the closure, so copy it
        // out under our own name.
        let finalURL = fm.temporaryDirectory.appendingPathComponent("\(folderName).zip")
        try? fm.removeItem(at: finalURL)
        var coordError: NSError?
        var didCopy = false
        NSFileCoordinator().coordinate(
            readingItemAt: stagingDir, options: [.forUploading], error: &coordError
        ) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: finalURL)
                didCopy = true
            } catch {
                logger.log("zip copy error: \(error.localizedDescription)")
            }
        }
        if let coordError {
            logger.log("zip coordinator error: \(coordError)")
            return nil
        }
        return didCopy ? finalURL : nil
    }

    /// File name used by every GPX export, like `20261024_Morning_Ride.gpx`.
    static func fileName(name: String, date: Date?) -> String {
        let stem =
            name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines))
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
        guard let date else { return "\(stem).gpx" }
        return "\(datePrefix(date))_\(stem).gpx"
    }

    static func datePrefix(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
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
