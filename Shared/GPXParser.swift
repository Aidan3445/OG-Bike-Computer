//
//  GPXParser.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation

class GPXParser: NSObject, XMLParserDelegate {
    private var routes: [Route] = []

    // Current track state
    private var currentTrackName: String?
    private var currentPoints: [TrackPoint] = []

    // Current point state
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentElevation: Double?

    // XML parse state
    private var currentElement: String = ""
    private var textBuffer: String = ""

    func parse(data: Data) -> [Route] {
        routes = []
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
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch element {
        case "name":
            // Only set track name if we haven't yet (first <name> inside <trk>)
            if currentTrackName == nil {
                currentTrackName = text
            }
        case "ele":
            currentElevation = Double(text)
        case "trkpt", "rtept":
            if let lat = currentLat, let lon = currentLon {
                let point = TrackPoint(
                    lat: lat,
                    lon: lon,
                    elevation: currentElevation)
                currentPoints.append(point)
            }
        case "trk", "rte":
            if !currentPoints.isEmpty {
                let route = Route(
                    id: UUID(),
                    name: currentTrackName ?? "Unnamed Route",
                    points: currentPoints)
                routes.append(route)
            }
        default:
            break
        }
    }
}
