//
//  GPXParser.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation

class GPXParser: NSObject, XMLParserDelegate {
    private var routes: [Route] = []

    private var currentTrackName: String?
    private var currentPoints: [TrackPoint] = []

    private var currentLat: Double?
    private var currentLon: Double?
    private var currentElevation: Double?

    private var currentElement: String = ""
    private var textBuffer: String = ""

    // Waypoint parsing state
    private var waypoints: [Waypoint] = []
    private var inWpt: Bool = false
    private var currentWptName: String?
    private var currentWptDesc: String?

    func parse(data: Data) -> [Route] {
        routes = []
        waypoints = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return routes
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = element
        textBuffer = ""

        switch element {
        case "trk":
            currentTrackName = nil
            currentPoints = []
        case "trkpt", "rtept":
            currentLat = Double(attributes["lat"] ?? "")
            currentLon = Double(attributes["lon"] ?? "")
            currentElevation = nil
        case "wpt":
            inWpt = true
            currentLat = Double(attributes["lat"] ?? "")
            currentLon = Double(attributes["lon"] ?? "")
            currentWptName = nil
            currentWptDesc = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?, qualifiedName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch element {
        case "name":
            if inWpt {
                currentWptName = text
            } else if currentTrackName == nil {
                currentTrackName = text
            }
        case "ele":
            currentElevation = Double(text)
        case "desc":
            if inWpt && !text.isEmpty {
                currentWptDesc = text
            }
        case "cmt":
            // Use cmt as fallback if desc wasn't set
            if inWpt && currentWptDesc == nil && !text.isEmpty {
                currentWptDesc = text
            }
        case "trkpt", "rtept":
            if let lat = currentLat, let lon = currentLon {
                let point = TrackPoint(
                    lat: lat,
                    lon: lon,
                    elevation: currentElevation)
                currentPoints.append(point)
            }
        case "wpt":
            if let lat = currentLat, let lon = currentLon, let name = currentWptName, !name.isEmpty {
                waypoints.append(Waypoint(
                    lat: lat,
                    lon: lon,
                    name: name,
                    description: currentWptDesc
                ))
            }
            inWpt = false
        case "trk", "rte":
            if !currentPoints.isEmpty {
                let route = Route(
                    id: UUID(),
                    name: currentTrackName ?? "Unnamed Route",
                    points: currentPoints,
                    waypoints: waypoints.isEmpty ? nil : waypoints)
                routes.append(route)
            }
        default:
            break
        }
    }
}
