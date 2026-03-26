import Foundation
import CoreLocation

// 1. Add Hashable here
struct CoordinatePoint: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Segment difficulty leaving this vertex toward the next (AI / Gemini). Omitted in Firestore for public routes.
    var condition: String?

    init(latitude: Double, longitude: Double, condition: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.condition = condition
    }

    var asCLLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// 2. Add Hashable here
struct TrekRoute: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var summary: String
    var distance: Double
    
    var startLatitude: Double
    var startLongitude: Double
    
    var weatherSummary: String?
    var estimatedDuration: String?
    // Mapped from OSM tags like `difficulty` or `osmc:symbol`.
    // Values are expected to be: `Easy`, `Moderate`, or `Hard`.
    var difficultyRating: String?
    var activityType: String?
    var routeCoordinates: [CoordinatePoint]?
    
    var startingCoordinate: CLLocationCoordinate2D {
        if let firstPoint = routeCoordinates?.first {
            return firstPoint.asCLLocationCoordinate
        }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }
}
