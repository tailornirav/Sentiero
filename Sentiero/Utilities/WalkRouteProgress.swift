import CoreLocation
import Foundation
import MapKit

/// Live walking stats along a coordinate-based route (polyline or single-point fallback).
struct WalkRouteProgress {
    var distanceCoveredMeters: Double
    var distanceRemainingMeters: Double
    var distanceAlongPathToNextVertexMeters: Double
    var nextVertexIndex: Int
    var totalPathMeters: Double
    var distanceFromPathMeters: Double
    var nextVertexCoordinate: CLLocationCoordinate2D?
    /// Map polyline trim: draw from this position on leg `trimLeadingSegmentIndex` at `trimLeadingSegmentT` (0…1). `nil` = full polyline.
    var trimLeadingSegmentIndex: Int?
    var trimLeadingSegmentT: Double

    static let walkingSpeedMPS: Double = 1.25

    func formattedDistanceKm(_ m: Double) -> String {
        String(format: "%.2f km", m / 1000)
    }

    func formattedMinutes(_ seconds: Double) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let rem = m % 60
        return rem > 0 ? "\(h) h \(rem) min" : "\(h) h"
    }

    var etaRemainingSeconds: Double {
        distanceRemainingMeters / Self.walkingSpeedMPS
    }

    var etaNextVertexSeconds: Double {
        distanceAlongPathToNextVertexMeters / Self.walkingSpeedMPS
    }
}

enum WalkRouteProgressCalculator {
    static func compute(userLocation: CLLocation, route: TrekRoute) -> WalkRouteProgress {
        if let coords = route.routeCoordinates, coords.count >= 2 {
            return computePolyline(userLocation: userLocation, coords: coords)
        }
        return computeDegenerate(userLocation: userLocation, route: route)
    }

    /// Keeps progress moving forward along the path (fixes loop routes snapping back to the start when GPS is near the trailhead again).
    static func computeWithMonotonicFloor(userLocation: CLLocation, route: TrekRoute, monotonicFloorMeters: Double) -> WalkRouteProgress {
        let raw = compute(userLocation: userLocation, route: route)
        guard let coords = route.routeCoordinates, coords.count >= 2 else {
            let covered = max(raw.distanceCoveredMeters, monotonicFloorMeters)
            if abs(covered - raw.distanceCoveredMeters) < 1 { return raw }
            var copy = raw
            copy.distanceCoveredMeters = covered
            copy.distanceRemainingMeters = max(0, raw.totalPathMeters - covered)
            copy.distanceAlongPathToNextVertexMeters = copy.distanceRemainingMeters
            return copy
        }

        let covered = max(raw.distanceCoveredMeters, monotonicFloorMeters)
        if covered <= raw.distanceCoveredMeters + 0.5 {
            return raw
        }
        return progressFromArcLength(coveredMeters: covered, coords: coords, userLocation: userLocation)
    }

    /// Build stats/trim for a known distance along the polyline (arc length from the first vertex).
    private static func progressFromArcLength(coveredMeters: Double, coords: [CoordinatePoint], userLocation: CLLocation) -> WalkRouteProgress {
        let n = coords.count
        var segLens: [Double] = []
        var cumulative: [Double] = [0]
        for i in 0..<(n - 1) {
            let a = MKMapPoint(coords[i].asCLLocationCoordinate)
            let b = MKMapPoint(coords[i + 1].asCLLocationCoordinate)
            let d = a.distance(to: b)
            segLens.append(d)
            cumulative.append(cumulative.last! + d)
        }
        let totalPath = cumulative.last ?? 0
        let covered = min(max(0, coveredMeters), totalPath)
        let remainingAlong = max(0, totalPath - covered)

        var segIdx = n - 2
        var t: Double = 1
        if totalPath > 0 {
            var i = 0
            while i < n - 1, cumulative[i + 1] < covered - 1e-6 {
                i += 1
            }
            segIdx = min(i, n - 2)
            let segStart = cumulative[segIdx]
            let len = segLens[segIdx]
            t = len > 1e-9 ? (covered - segStart) / len : 0
            t = min(1, max(0, t))
        }

        let pa = MKMapPoint(coords[segIdx].asCLLocationCoordinate)
        let pb = MKMapPoint(coords[segIdx + 1].asCLLocationCoordinate)
        let interp = MKMapPoint(x: pa.x + t * (pb.x - pa.x), y: pa.y + t * (pb.y - pa.y))
        let distFromPath = userLocation.distance(from: CLLocation(latitude: interp.coordinate.latitude, longitude: interp.coordinate.longitude))

        var nextIndex = n - 1
        for j in 1..<n {
            if cumulative[j] > covered + 0.5 {
                nextIndex = j
                break
            }
        }
        let alongToNext = max(0, cumulative[nextIndex] - covered)
        let nextCoord: CLLocationCoordinate2D? = nextIndex < n ? coords[nextIndex].asCLLocationCoordinate : nil

        return WalkRouteProgress(
            distanceCoveredMeters: covered,
            distanceRemainingMeters: remainingAlong,
            distanceAlongPathToNextVertexMeters: alongToNext,
            nextVertexIndex: nextIndex,
            totalPathMeters: totalPath,
            distanceFromPathMeters: distFromPath,
            nextVertexCoordinate: nextCoord,
            trimLeadingSegmentIndex: segIdx,
            trimLeadingSegmentT: t
        )
    }

    private static func computePolyline(userLocation: CLLocation, coords: [CoordinatePoint]) -> WalkRouteProgress {
        let n = coords.count
        var segLens: [Double] = []
        segLens.reserveCapacity(n - 1)
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(n)
        for i in 0..<(n - 1) {
            let a = MKMapPoint(coords[i].asCLLocationCoordinate)
            let b = MKMapPoint(coords[i + 1].asCLLocationCoordinate)
            let d = a.distance(to: b)
            segLens.append(d)
            cumulative.append(cumulative.last! + d)
        }
        let totalPath = cumulative.last ?? 0

        let userPoint = MKMapPoint(userLocation.coordinate)
        var bestSeg = 0
        var bestT: Double = 0
        var bestDistFromUser = Double.greatestFiniteMagnitude

        for i in 0..<(n - 1) {
            let a = MKMapPoint(coords[i].asCLLocationCoordinate)
            let b = MKMapPoint(coords[i + 1].asCLLocationCoordinate)
            let (_, t, dUser) = closestPointOnSegment(p: userPoint, a: a, b: b)
            if dUser < bestDistFromUser {
                bestDistFromUser = dUser
                bestSeg = i
                bestT = t
            }
        }

        let coveredAlong = cumulative[bestSeg] + bestT * segLens[bestSeg]
        let clampedCovered = min(max(0, coveredAlong), totalPath)
        let remainingAlong = max(0, totalPath - clampedCovered)

        var nextIndex = n - 1
        for j in 1..<n {
            if cumulative[j] > clampedCovered + 0.5 {
                nextIndex = j
                break
            }
        }

        let alongToNext = max(0, cumulative[nextIndex] - clampedCovered)
        let nextCoord: CLLocationCoordinate2D? = nextIndex < n ? coords[nextIndex].asCLLocationCoordinate : nil

        return WalkRouteProgress(
            distanceCoveredMeters: clampedCovered,
            distanceRemainingMeters: remainingAlong,
            distanceAlongPathToNextVertexMeters: alongToNext,
            nextVertexIndex: nextIndex,
            totalPathMeters: totalPath,
            distanceFromPathMeters: bestDistFromUser,
            nextVertexCoordinate: nextCoord,
            trimLeadingSegmentIndex: bestSeg,
            trimLeadingSegmentT: bestT
        )
    }

    private static func computeDegenerate(userLocation: CLLocation, route: TrekRoute) -> WalkRouteProgress {
        let startCoord = route.startingCoordinate
        let startLoc = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        let fromStart = userLocation.distance(from: startLoc)
        let totalMeters = max(route.distance * 1000, fromStart)

        let covered = min(fromStart, totalMeters)
        let remaining = max(0, totalMeters - covered)

        return WalkRouteProgress(
            distanceCoveredMeters: covered,
            distanceRemainingMeters: remaining,
            distanceAlongPathToNextVertexMeters: remaining,
            nextVertexIndex: 0,
            totalPathMeters: totalMeters,
            distanceFromPathMeters: 0,
            nextVertexCoordinate: startCoord,
            trimLeadingSegmentIndex: nil,
            trimLeadingSegmentT: 0
        )
    }

    private static func closestPointOnSegment(p: MKMapPoint, a: MKMapPoint, b: MKMapPoint) -> (MKMapPoint, Double, Double) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 {
            let d = p.distance(to: a)
            return (a, 0, d)
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(1, max(0, t))
        let cx = a.x + t * dx
        let cy = a.y + t * dy
        let c = MKMapPoint(x: cx, y: cy)
        return (c, t, p.distance(to: c))
    }

    /// Bearing from `from` to `to` in degrees, 0 = north (for map heading when course is invalid).
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let φ1 = from.latitude * .pi / 180
        let φ2 = to.latitude * .pi / 180
        let Δλ = (to.longitude - from.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x)
        let deg = θ * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}
