import SwiftUI
import CoreLocation
import MapKit

enum RoutePolylineStyle {
    /// Red = severe/hard, yellow = moderate, blue = easy or unknown.
    static func strokeColor(forDifficultyOrCondition raw: String?) -> Color {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch s {
        case "hard", "severe", "extreme", "difficult", "very hard":
            return .red
        case "moderate", "medium", "intermediate":
            return .yellow
        default:
            return .blue
        }
    }

    static let lineStyle = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    static let lineStyleCompact = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)

    /// Per-segment colors from each coordinate's `condition` on the leg leaving that vertex. Missing → **blue**.
    static func strokeSegments(for route: TrekRoute) -> [(coordinates: [CLLocationCoordinate2D], color: Color)] {
        guard let coords = route.routeCoordinates, coords.count > 1 else { return [] }
        return strokeSegments(from: coords)
    }

    static func strokeSegments(from coords: [CoordinatePoint]) -> [(coordinates: [CLLocationCoordinate2D], color: Color)] {
        guard coords.count > 1 else { return [] }

        let hasAnySegment = coords.dropLast().contains { $0.condition != nil }
        if !hasAnySegment {
            return [(coords.map { $0.asCLLocationCoordinate }, .blue)]
        }

        var segments: [(coordinates: [CLLocationCoordinate2D], color: Color)] = []
        var chunk: [CLLocationCoordinate2D] = [coords[0].asCLLocationCoordinate]
        var currentColor = strokeColor(forDifficultyOrCondition: coords[0].condition)

        for i in 0..<(coords.count - 1) {
            let segColor = strokeColor(forDifficultyOrCondition: coords[i].condition)
            if segColor == currentColor {
                chunk.append(coords[i + 1].asCLLocationCoordinate)
            } else {
                segments.append((chunk, currentColor))
                chunk = [coords[i].asCLLocationCoordinate, coords[i + 1].asCLLocationCoordinate]
                currentColor = segColor
            }
        }
        segments.append((chunk, currentColor))
        return segments
    }

    /// Remaining path while walking: from projected position on leg `leadingSegmentIndex` at `leadingT` (0…1) to the end.
    static func strokeSegmentsRemaining(
        coords: [CoordinatePoint],
        leadingSegmentIndex: Int,
        leadingT: Double
    ) -> [(coordinates: [CLLocationCoordinate2D], color: Color)] {
        let n = coords.count
        guard n > 1, leadingSegmentIndex >= 0, leadingSegmentIndex < n - 1 else {
            return strokeSegments(from: coords)
        }

        let pa = MKMapPoint(coords[leadingSegmentIndex].asCLLocationCoordinate)
        let pb = MKMapPoint(coords[leadingSegmentIndex + 1].asCLLocationCoordinate)
        let t = min(1, max(0, leadingT))
        let interp = MKMapPoint(x: pa.x + t * (pb.x - pa.x), y: pa.y + t * (pb.y - pa.y))
        let interpCoord = interp.coordinate

        var tail: [CoordinatePoint] = []
        let legCondition = coords[leadingSegmentIndex].condition
        tail.append(CoordinatePoint(latitude: interpCoord.latitude, longitude: interpCoord.longitude, condition: legCondition))
        for j in (leadingSegmentIndex + 1)..<n {
            tail.append(coords[j])
        }

        if tail.count >= 2 {
            let d = MKMapPoint(tail[0].asCLLocationCoordinate).distance(to: MKMapPoint(tail[1].asCLLocationCoordinate))
            if d < 2 {
                tail.removeFirst()
            }
        }

        guard tail.count > 1 else { return [] }
        return strokeSegments(from: tail)
    }
}
