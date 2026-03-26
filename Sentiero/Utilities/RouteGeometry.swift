import CoreLocation
import Foundation

enum RouteGeometry {
    /// Start and end are the same place (or very close) — treat as a loop for completion logic.
    static func isLoop(route: TrekRoute, thresholdMeters: CLLocationDistance = 80) -> Bool {
        guard let coords = route.routeCoordinates, let first = coords.first, let last = coords.last else {
            return false
        }
        let a = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let b = CLLocation(latitude: last.latitude, longitude: last.longitude)
        return a.distance(from: b) <= thresholdMeters
    }

    static func endCoordinate(for route: TrekRoute) -> CLLocationCoordinate2D {
        if let last = route.routeCoordinates?.last {
            return last.asCLLocationCoordinate
        }
        return route.startingCoordinate
    }
}
