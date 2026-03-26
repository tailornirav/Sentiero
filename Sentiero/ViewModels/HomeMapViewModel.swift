import Foundation
import CoreLocation
import SwiftUI
import MapKit
import Combine

@MainActor
class HomeMapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var nearbyRoutes: [TrekRoute] = []
    @Published var selectedRoute: TrekRoute? = nil
    @Published var isLoadingRoutes: Bool = true
    @Published var currentWeather: WeatherInfo? = nil
    @Published var isAtTrailhead: Bool = false
    @Published var isTrackingWalk: Bool = false
    @Published var walkProgress: WalkRouteProgress?
    @Published var walkCompletionSummary: WalkCompletionSummary?
    
    /// Trailhead detection uses the same point as the green Start marker (`startingCoordinate` = first polyline point when present).
    private static let trailheadProximityMeters: CLLocationDistance = 150
    private static let monotonicSlackMeters: Double = 35
    private static let autoCompleteNearEndMeters: CLLocationDistance = 85
    /// For loops: must have covered this fraction of polyline length before “back at start” counts as done.
    private static let loopCompletedMinFraction: Double = 0.82
    private static let linearMinProgressFraction: Double = 0.3
    private static let minWalkBeforeAutoCompleteMeters: Double = 100
    
    /// Highest arc-length covered along the route this session (stops loop routes from snapping backward near the start).
    private var walkMaxProgressAlongPath: Double = 0
    /// Set when the user starts tracking; used for Apple Health workout duration.
    private var walkSessionStart: Date?

    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private var allPublicRoutes: [TrekRoute] = []
    private var hasSortedNearbyRoutes = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        fetchRoutesFromCloud()
        
        GlobalRouter.shared.$routeToFocusOnMap
            .compactMap { $0 }
            .sink { [weak self] routeToFocus in
                self?.focusOnRoute(routeToFocus)
                GlobalRouter.shared.routeToFocusOnMap = nil
            }
            .store(in: &cancellables)
    }
    
    func focusOnRoute(_ route: TrekRoute) {
        selectedRoute = route
        currentWeather = nil
        
        cameraPosition = .region(MKCoordinateRegion(
            center: route.startingCoordinate,
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        ))
        
        WeatherService.shared.fetchWeather(latitude: route.startLatitude, longitude: route.startLongitude) { [weak self] liveWeather in
            DispatchQueue.main.async {
                self?.currentWeather = liveWeather
            }
        }
        
        locationManager.requestLocation()
        applyTrailheadAndWalkProgressIfPossible()
        
        // Public routes: ask Gemini for per-leg difficulty (non-throwing — failures keep default blue polyline).
        Task { [weak self] in
            let updated = await GeminiService.shared.analyzeRouteConditions(for: route)
            await MainActor.run {
                guard let self else { return }
                guard self.selectedRoute?.id == updated.id else { return }
                self.selectedRoute = updated
                if let idx = self.allPublicRoutes.firstIndex(where: { $0.id == updated.id }) {
                    self.allPublicRoutes[idx] = updated
                }
                if let idx = self.nearbyRoutes.firstIndex(where: { $0.id == updated.id }) {
                    self.nearbyRoutes[idx] = updated
                }
                DatabaseService.shared.mergeEnrichedRouteIntoCache(updated)
            }
        }
    }
    
    func clearSelection() {
        selectedRoute = nil
        currentWeather = nil
        cameraPosition = .userLocation(fallback: .automatic)
        isAtTrailhead = false
        isTrackingWalk = false
        walkProgress = nil
        walkCompletionSummary = nil
        walkMaxProgressAlongPath = 0
        walkSessionStart = nil
    }
    
    func beginTrackingWalk() {
        isTrackingWalk = true
        walkMaxProgressAlongPath = 0
        walkCompletionSummary = nil
        walkSessionStart = Date()
        applyTrailheadAndWalkProgressIfPossible()
    }
    
    func requestManualWalkEnd() {
        guard let route = selectedRoute else { return }
        presentWalkCompletion(route: route, kind: .endedEarly)
    }
    
    /// After the celebration sheet: save stats, clear the map, optionally open Profile.
    func confirmWalkCompletion(navigateToProfile: Bool) {
        guard let route = selectedRoute, walkCompletionSummary != nil else {
            walkCompletionSummary = nil
            return
        }
        let walkedMeters = max(walkMaxProgressAlongPath, 10)
        let sessionEnd = Date()
        let sessionStart = walkSessionStart ?? sessionEnd.addingTimeInterval(-min(3 * 3600, walkedMeters / 1.3))
        let routeName = route.name

        LocalProfileManager.shared.addCompletedRoute(distance: route.distance)
        walkCompletionSummary = nil
        walkMaxProgressAlongPath = 0
        walkSessionStart = nil
        withAnimation {
            clearSelection()
        }
        if navigateToProfile {
            GlobalRouter.shared.activeTab = 4
        }

        Task {
            await HealthKitManager.shared.saveHikingWorkout(
                routeName: routeName,
                start: sessionStart,
                end: sessionEnd,
                distanceMeters: walkedMeters
            )
        }
    }
    
    /// Call after toggling `isTrackingWalk` on so stats/camera update immediately if GPS is already available.
    func applyTrailheadAndWalkProgressIfPossible() {
        guard let loc = locationManager.location else { return }
        applyLocationUpdate(loc)
    }
    
    /// Difficulty label for the path segment leading toward the upcoming checkpoint (Gemini `condition` on the vertex).
    func upcomingSegmentCondition(route: TrekRoute, progress: WalkRouteProgress) -> String? {
        guard let coords = route.routeCoordinates, progress.nextVertexIndex > 0 else { return nil }
        let i = progress.nextVertexIndex - 1
        guard i < coords.count else { return nil }
        let c = coords[i].condition?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (c?.isEmpty == false) ? c : nil
    }
    
    private func applyLocationUpdate(_ currentLocation: CLLocation) {
        if walkCompletionSummary != nil {
            return
        }
        
        if let route = selectedRoute {
            let startLocation = CLLocation(
                latitude: route.startingCoordinate.latitude,
                longitude: route.startingCoordinate.longitude
            )
            let distanceInMeters = currentLocation.distance(from: startLocation)
            let atStart = distanceInMeters <= Self.trailheadProximityMeters
            isAtTrailhead = atStart
            
            if isTrackingWalk {
                let floor = max(0, walkMaxProgressAlongPath - Self.monotonicSlackMeters)
                let progress = WalkRouteProgressCalculator.computeWithMonotonicFloor(
                    userLocation: currentLocation,
                    route: route,
                    monotonicFloorMeters: floor
                )
                walkMaxProgressAlongPath = max(walkMaxProgressAlongPath, progress.distanceCoveredMeters)
                walkProgress = progress
                updateTrackingCamera(userLocation: currentLocation, progress: progress)
                checkWalkAutoComplete(route: route, progress: progress, userLocation: currentLocation)
            } else {
                walkProgress = nil
            }
        } else {
            isAtTrailhead = false
            walkProgress = nil
        }
    }
    
    private func checkWalkAutoComplete(route: TrekRoute, progress: WalkRouteProgress, userLocation: CLLocation) {
        guard walkCompletionSummary == nil else { return }
        let total = progress.totalPathMeters
        guard total > 40 else { return }
        
        let minAlong = max(Self.minWalkBeforeAutoCompleteMeters, total * Self.linearMinProgressFraction)
        guard walkMaxProgressAlongPath >= minAlong else { return }
        
        if RouteGeometry.isLoop(route: route) {
            let startLoc = CLLocation(
                latitude: route.startingCoordinate.latitude,
                longitude: route.startingCoordinate.longitude
            )
            let nearStartAgain = userLocation.distance(from: startLoc) <= Self.trailheadProximityMeters * 1.25
            let loopFractionOk = walkMaxProgressAlongPath >= total * Self.loopCompletedMinFraction
            if nearStartAgain && loopFractionOk {
                presentWalkCompletion(route: route, kind: .completedLoop)
            }
        } else {
            let endCoord = RouteGeometry.endCoordinate(for: route)
            let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
            let nearEnd = userLocation.distance(from: endLoc) <= Self.autoCompleteNearEndMeters
            let lowRemaining = progress.distanceRemainingMeters < 95
            if nearEnd && lowRemaining {
                presentWalkCompletion(route: route, kind: .reachedDestination)
            }
        }
    }
    
    private func presentWalkCompletion(route: TrekRoute, kind: WalkCompletionSummary.Kind) {
        guard walkCompletionSummary == nil else { return }
        walkCompletionSummary = WalkCompletionSummary(routeName: route.name, routeDistanceKm: route.distance, kind: kind)
        isTrackingWalk = false
        walkProgress = nil
        if kind != .endedEarly {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: route.startingCoordinate,
                    latitudinalMeters: 2500,
                    longitudinalMeters: 2500
                )
            )
        }
    }
    
    private func updateTrackingCamera(userLocation: CLLocation, progress: WalkRouteProgress) {
        let heading: CLLocationDirection
        if userLocation.course >= 0 {
            heading = userLocation.course
        } else if let next = progress.nextVertexCoordinate {
            heading = WalkRouteProgressCalculator.bearing(from: userLocation.coordinate, to: next)
        } else {
            heading = 0
        }
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: userLocation.coordinate,
                distance: 450,
                heading: heading,
                pitch: 50
            )
        )
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let currentLocation = locations.last else { return }
        
        DispatchQueue.main.async {
            self.applyLocationUpdate(currentLocation)
            
            if !self.allPublicRoutes.isEmpty && !self.hasSortedNearbyRoutes {
                self.updateNearbyRoutes()
                self.hasSortedNearbyRoutes = true
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Required on recent iOS; `requestLocation()` can fail (e.g. transient kCLErrorLocationUnknown).
        let code = (error as NSError).code
        if code != CLError.locationUnknown.rawValue {
            #if DEBUG
            print("HomeMapViewModel location error: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func fetchRoutesFromCloud() {
        isLoadingRoutes = true
        DatabaseService.shared.fetchPublicRoutes { [weak self] liveRoutes in
            DispatchQueue.main.async {
                self?.allPublicRoutes = liveRoutes
                self?.updateNearbyRoutes()
                self?.isLoadingRoutes = false
            }
        }
    }
    
    private func updateNearbyRoutes() {
        guard let userLocation = locationManager.location else {
            nearbyRoutes = Array(allPublicRoutes.prefix(5))
            return
        }
        let sorted = allPublicRoutes.sorted { route1, route2 in
            let loc1 = CLLocation(latitude: route1.startLatitude, longitude: route1.startLongitude)
            let loc2 = CLLocation(latitude: route2.startLatitude, longitude: route2.startLongitude)
            return userLocation.distance(from: loc1) < userLocation.distance(from: loc2)
        }
        nearbyRoutes = Array(sorted.prefix(5))
    }
}
