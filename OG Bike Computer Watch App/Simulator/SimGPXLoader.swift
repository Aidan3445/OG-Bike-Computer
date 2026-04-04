//
//  SimGPXLoader.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/6/26.
//

#if DEBUG
import Foundation
import CoreLocation

struct SimGPXLoader {

    struct SimTrack {
        let name: String
        let locations: [CLLocation]
    }

   static func loadAll() -> [SimTrack] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) else {
            print("[Sim] No GPX files found in bundle")
            return []
        }
        print("[Sim] Found \(urls.count) GPX files")
        return urls.compactMap { load(url: $0) }
    }

    static func load(url: URL) -> SimTrack? {
        guard let data = try? Data(contentsOf: url) else {
            print("[Sim] Failed to read: \(url.lastPathComponent)")
            return nil
        }
        let parser = SimGPXParser()
        let locations = parser.parse(data: data)
        guard !locations.isEmpty else {
            print("[Sim] No points parsed from: \(url.lastPathComponent)")
            return nil
        }
        let name = parser.trackName ?? url.deletingPathExtension().lastPathComponent
        print("[Sim] Loaded \(name): \(locations.count) points")
        return SimTrack(name: name, locations: locations)
    }
}

private class SimGPXParser: NSObject, XMLParserDelegate {
    var trackName: String?
    private(set) var locations: [CLLocation] = []

    private var currentElement = ""
    private var currentText = ""

    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?

    private var inTrkpt = false
    private var inTrkName = false

    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let dateFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func parse(data: Data) -> [CLLocation] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return locations
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = element
        currentText = ""

        if element == "trkpt" || element == "rtept" {
            inTrkpt = true
            currentLat = attributes["lat"].flatMap(Double.init)
            currentLon = attributes["lon"].flatMap(Double.init)
            currentEle = nil
            currentTime = nil
        }

        if element == "name" && !inTrkpt && trackName == nil {
            inTrkName = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inTrkpt {
            if element == "ele" {
                currentEle = Double(trimmed)
            } else if element == "time" {
                currentTime = dateFormatter.date(from: trimmed)
                    ?? dateFormatterNoFrac.date(from: trimmed)
            } else if element == "trkpt" || element == "rtept" {
                if let lat = currentLat, let lon = currentLon {
                    let location = CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        altitude: currentEle ?? 0,
                        horizontalAccuracy: 5,
                        verticalAccuracy: 5,
                        course: -1,
                        speed: -1,
                        timestamp: currentTime ?? Date())
                    locations.append(location)
                }
                inTrkpt = false
            }
        }

        if element == "name" && inTrkName {
            trackName = trimmed
            inTrkName = false
        }

        currentText = ""
    }
}
#endif
