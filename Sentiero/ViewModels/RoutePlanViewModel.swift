import Combine
import CoreLocation
import Foundation

@MainActor
class RoutePlanViewModel: ObservableObject {
    
    @Published var plan: RoutePlan
    @Published var isGeneratingChecklist: Bool = false

    @Published var isEditingRoute: Bool = false
    @Published var isRecalculatingRoute: Bool = false
    @Published var editWaypoints: [CLLocationCoordinate2D] = []
    @Published var editDisplayPolyline: [CLLocationCoordinate2D] = []
    /// Bumps when entering route edit so the map recenters once.
    @Published var routeEditMapFitToken: Int = 0

    private var routeRecalcTask: Task<Void, Never>?
    private var routeRecalcGeneration: Int = 0
    /// Wait after last pin move before calling Directions (avoids GEO 50/min throttling).
    private static let routeRecalcDebounceNanoseconds: UInt64 = 2_000_000_000
    
    init(plan: RoutePlan) {
        self.plan = plan
        
        // CRITICAL LOGIC: Only invoke Gemini if the checklist array is mathematically empty.
        if self.plan.checklist.isEmpty {
            generateAIChecklist()
        }
    }

    func enterRouteEditing() {
        routeRecalcTask?.cancel()
        routeEditMapFitToken += 1
        editWaypoints = Self.waypointSeeds(from: plan.route)
        editDisplayPolyline = []
        isEditingRoute = true
        routeRecalcTask = Task { await self.performRouteRecalc() }
    }

    func cancelRouteEditing() {
        routeRecalcTask?.cancel()
        routeRecalcTask = nil
        isEditingRoute = false
        isRecalculatingRoute = false
        editWaypoints = []
        editDisplayPolyline = []
    }

    /// Debounced: rapid pin moves coalesce into one Directions batch.
    func schedulePolylineRecalculation() {
        routeRecalcTask?.cancel()
        routeRecalcTask = Task {
            try? await Task.sleep(nanoseconds: Self.routeRecalcDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.performRouteRecalc()
        }
    }

    private func performRouteRecalc() async {
        guard isEditingRoute else { return }
        routeRecalcGeneration += 1
        let generation = routeRecalcGeneration
        isRecalculatingRoute = true
        let pts = editWaypoints
        do {
            let line = try await RouteCalculator.walkingPolyline(through: pts)
            try Task.checkCancellation()
            guard isEditingRoute else {
                isRecalculatingRoute = false
                return
            }
            guard generation == routeRecalcGeneration else { return }
            editDisplayPolyline = line
            isRecalculatingRoute = false
        } catch is CancellationError {
            if generation == routeRecalcGeneration {
                isRecalculatingRoute = false
            }
        } catch {
            guard isEditingRoute else {
                isRecalculatingRoute = false
                return
            }
            guard generation == routeRecalcGeneration else { return }
            editDisplayPolyline = pts
            isRecalculatingRoute = false
        }
    }

    func saveEditedRoute() {
        let coords: [CLLocationCoordinate2D]
        if editDisplayPolyline.count >= 2 {
            coords = editDisplayPolyline
        } else if editWaypoints.count >= 2 {
            coords = editWaypoints
        } else {
            return
        }

        var r = plan.route
        r.routeCoordinates = coords.map { CoordinatePoint(latitude: $0.latitude, longitude: $0.longitude, condition: nil) }
        if let f = coords.first {
            r.startLatitude = f.latitude
            r.startLongitude = f.longitude
        }
        r.distance = max(0.01, RouteCalculator.pathLengthKm(along: coords))
        plan.route = r
        LocalPlanManager.shared.savePlan(plan)
        cancelRouteEditing()
    }

    private static func waypointSeeds(from route: TrekRoute) -> [CLLocationCoordinate2D] {
        let raw = route.routeCoordinates?.map(\.asCLLocationCoordinate) ?? []
        if raw.isEmpty {
            let s = route.startingCoordinate
            let e = CLLocationCoordinate2D(latitude: s.latitude + 0.003, longitude: s.longitude + 0.003)
            return [s, e]
        }
        if raw.count == 1 {
            let s = raw[0]
            return [s, CLLocationCoordinate2D(latitude: s.latitude + 0.003, longitude: s.longitude + 0.003)]
        }
        if raw.count > 18 {
            return downsampleCoordinates(raw, maxPoints: 18)
        }
        return raw
    }

    private static func downsampleCoordinates(_ coords: [CLLocationCoordinate2D], maxPoints k: Int) -> [CLLocationCoordinate2D] {
        let n = coords.count
        guard n > k, k >= 2 else { return coords }
        var out: [CLLocationCoordinate2D] = []
        for i in 0..<k {
            let j = Int(round(Double(i) * Double(n - 1) / Double(k - 1)))
            out.append(coords[j])
        }
        return out
    }
    
    func toggleItem(id: String) {
        if let index = plan.checklist.firstIndex(where: { $0.id == id }) {
            plan.checklist[index].isCompleted.toggle()
            // Immediately write the state flip to the physical hard drive
            LocalPlanManager.shared.savePlan(self.plan)
        }
    }

    func setPlanDisplayTitle(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var p = plan
        p.displayTitle = t
        plan = p
        LocalPlanManager.shared.savePlan(plan)
    }
    
    private func generateAIChecklist() {
        isGeneratingChecklist = true
        
        Task {
            do {
                let generatedItems = try await GeminiService.shared.generateChecklist(for: self.plan.route)
                self.plan.checklist = generatedItems
                // Save the AI's results to the hard drive immediately
                LocalPlanManager.shared.savePlan(self.plan)
            } catch {
                print("Failed to generate AI checklist: \(error.localizedDescription)")
            }
            self.isGeneratingChecklist = false
        }
    }
    
    var groupedChecklist: [String: [ChecklistItem]] {
        Dictionary(grouping: plan.checklist, by: { $0.category })
    }

    /// Built-in sections first (in fixed order), then any extra Gemini categories alphabetically.
    var categoryDisplayOrder: [String] {
        let keys = Set(plan.checklist.map(\.category))
        var ordered: [String] = []
        for c in ChecklistItem.builtInCategories where keys.contains(c) {
            ordered.append(c)
        }
        let extras = keys.subtracting(ordered).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return ordered + extras
    }
}
