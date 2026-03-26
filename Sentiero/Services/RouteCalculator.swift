import CoreLocation
import Foundation
import MapKit

/// Builds a continuous walking path through waypoints using `MKDirections`, with straight-line fallback per leg.
enum RouteCalculator {

    /// Legs shorter than this use a straight segment (no Directions request) to reduce GEO throttling.
    private static let straightLineLegThresholdMeters: CLLocationDistance = 750

    /// Extra pause after the global rate limiter when chaining many walking legs.
    private static let delayBetweenDirectionsNanoseconds: UInt64 = 280_000_000

    static func walkingPolyline(through waypoints: [CLLocationCoordinate2D]) async throws -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { return waypoints }

        var master: [CLLocationCoordinate2D] = []
        master.reserveCapacity(waypoints.count * 8)

        var previousLegUsedDirections = false
        for i in 0..<(waypoints.count - 1) {
            try Task.checkCancellation()

            let a = waypoints[i]
            let b = waypoints[i + 1]
            let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
            let legMeters = la.distance(from: lb)

            let segment: [CLLocationCoordinate2D]
            if legMeters < straightLineLegThresholdMeters {
                segment = [a, b]
            } else {
                if previousLegUsedDirections {
                    try await Task.sleep(nanoseconds: delayBetweenDirectionsNanoseconds)
                    try Task.checkCancellation()
                }
                segment = try await walkingSegment(from: a, to: b)
                previousLegUsedDirections = true
            }

            if master.isEmpty {
                master.append(contentsOf: segment)
            } else if !segment.isEmpty {
                let first = segment[0]
                let last = master.last!
                if abs(first.latitude - last.latitude) < 1e-7, abs(first.longitude - last.longitude) < 1e-7 {
                    master.append(contentsOf: segment.dropFirst())
                } else {
                    master.append(contentsOf: segment)
                }
            }
        }

        return master.isEmpty ? waypoints : master
    }

    private static func walkingSegment(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D] {
        try await DirectionsRateLimiter.shared.acquireSlot()

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .walking

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            let coords: [CLLocationCoordinate2D]
            if let route = response.routes.first {
                coords = coordinates(from: route.polyline)
            } else {
                coords = [start, end]
            }
            await DirectionsRateLimiter.shared.markRequestCompleted()
            return coords
        } catch is CancellationError {
            await DirectionsRateLimiter.shared.markRequestCompleted()
            throw CancellationError()
        } catch {
            await DirectionsRateLimiter.shared.markRequestCompleted()
            return [start, end]
        }
    }

    static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let n = polyline.pointCount
        guard n > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: n)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: n))
        return coords
    }

    static func pathLengthKm(along coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var meters: Double = 0
        for i in 0..<(coordinates.count - 1) {
            let a = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            let b = CLLocation(latitude: coordinates[i + 1].latitude, longitude: coordinates[i + 1].longitude)
            meters += a.distance(from: b)
        }
        return meters / 1000
    }
}
