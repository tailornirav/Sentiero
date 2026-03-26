import Foundation
import FirebaseFirestore

/// Normalizes Firestore route coordinate payloads so map polylines match tools that plot raw DB data.
enum FirestoreCoordinateParsing {

    static func parseCoordinateArray(from data: [String: Any], key: String = "routeCoordinates") -> [CoordinatePoint]? {
        guard let raw = data[key] else { return nil }

        if let arr = raw as? [[String: Any]] {
            let pts = arr.compactMap { point(fromDict: $0) }
            return pts.isEmpty ? nil : sanitizeOrder(pts)
        }
        if let arr = raw as? [Any] {
            let pts = arr.compactMap { point(fromAny: $0) }
            return pts.isEmpty ? nil : sanitizeOrder(pts)
        }
        if let map = raw as? [String: Any] {
            var temp: [CoordinatePoint] = []
            let sortedKeys = map.keys.compactMap { Int($0) }.sorted()
            for k in sortedKeys {
                if let dict = map[String(k)] as? [String: Any],
                   let p = point(fromDict: dict) {
                    temp.append(p)
                }
            }
            return temp.isEmpty ? nil : sanitizeOrder(temp)
        }
        return nil
    }

    private static func point(fromAny element: Any) -> CoordinatePoint? {
        if let dict = element as? [String: Any] {
            return point(fromDict: dict)
        }
        if let geo = element as? GeoPoint {
            return CoordinatePoint(latitude: geo.latitude, longitude: geo.longitude, condition: nil)
        }
        return nil
    }

    private static func point(fromDict dict: [String: Any]) -> CoordinatePoint? {
        let lat = double(forKeys: ["latitude", "lat", "Latitude"], in: dict)
        let lon = double(forKeys: ["longitude", "lon", "lng", "long", "Longitude"], in: dict)
        guard var lat, var lon else { return nil }

        // Obvious invalid pair (common data-entry swap)
        if abs(lat) > 90, abs(lon) <= 90 {
            swap(&lat, &lon)
        }
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }

        let cond = dict["condition"] as? String
        return CoordinatePoint(latitude: lat, longitude: lon, condition: cond)
    }

    private static func double(forKeys keys: [String], in dict: [String: Any]) -> Double? {
        for k in keys {
            guard let v = dict[k] else { continue }
            if let d = v as? Double { return d }
            if let n = v as? NSNumber { return n.doubleValue }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String, let d = Double(s) { return d }
        }
        return nil
    }

    /// Drop consecutive duplicates (stops zero-length Map segments that confuse SwiftUI Map).
    private static func sanitizeOrder(_ pts: [CoordinatePoint]) -> [CoordinatePoint] {
        guard !pts.isEmpty else { return pts }
        var out: [CoordinatePoint] = [pts[0]]
        for i in 1..<pts.count {
            let a = out.last!
            let b = pts[i]
            let same = abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
            if !same { out.append(b) }
        }
        return out
    }
}
