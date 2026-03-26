import SwiftUI
import MapKit

struct HomeMapView: View {
    @StateObject private var viewModel = HomeMapViewModel()
    @State private var isExpanded = false
    @State private var walkStatsMinimized = false
    
    var body: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()
            
            if let selected = viewModel.selectedRoute {
                if let coords = selected.routeCoordinates, coords.count > 1 {
                    let segments = strokeSegmentsForMap(route: selected, coords: coords)
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        MapPolyline(coordinates: Array(seg.coordinates))
                            .stroke(seg.color, style: RoutePolylineStyle.lineStyle)
                    }
                    
                    if let start = coords.first, let end = coords.last {
                        if !viewModel.isTrackingWalk {
                            Marker("Start", systemImage: iconForActivity(selected.activityType), coordinate: start.asCLLocationCoordinate)
                                .tint(.green)
                        }
                        if start != end {
                            Marker("End", systemImage: "flag.checkered", coordinate: end.asCLLocationCoordinate)
                                .tint(.red)
                        }
                    }
                } else {
                    // Fallback for routes that only have a starting coordinate
                    Marker(selected.name, systemImage: iconForActivity(selected.activityType), coordinate: selected.startingCoordinate)
                        .tint(.blue)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .animation(.easeInOut(duration: 1.0), value: viewModel.cameraPosition)
        .safeAreaInset(edge: .bottom) {
            if let summary = viewModel.walkCompletionSummary {
                buildWalkCompletionCard(summary)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let selectedRoute = viewModel.selectedRoute {
                buildActionCard(for: selectedRoute)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                buildNearbyRoutesDrawer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.selectedRoute != nil)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.walkCompletionSummary != nil)
        .onChange(of: viewModel.isTrackingWalk) { _, isOn in
            if isOn { walkStatsMinimized = false }
        }
        .onChange(of: viewModel.selectedRoute?.id) { _, _ in
            walkStatsMinimized = false
        }
    }
    
    // MARK: - UI Components
    @ViewBuilder
    private func buildActionCard(for route: TrekRoute) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack(alignment: .top) {
                if viewModel.isTrackingWalk {
                    Label("On route", systemImage: "figure.walk.motion")
                        .font(.headline.weight(.semibold))
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(route.summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Button {
                    viewModel.clearSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            
            if !viewModel.isTrackingWalk {
                HStack(spacing: 20) {
                    Label("\(String(format: "%.1f", route.distance)) km", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption).fontWeight(.semibold)
                    
                    if let weather = viewModel.currentWeather {
                        Label("\(Int(weather.temperature))°C, \(weather.condition)", systemImage: weather.systemIconName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    } else {
                        Label("Weather Syncing...", systemImage: "cloud.sun")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            VStack(spacing: 12) {
                
                if !viewModel.isTrackingWalk {
                    Button(action: {
                        let plan: RoutePlan
                        if let existing = LocalPlanManager.shared.existingPlan(forRouteId: route.id) {
                            plan = existing
                        } else {
                            plan = RoutePlan(route: route, checklist: [])
                            LocalPlanManager.shared.savePlan(plan)
                        }
                        var path = NavigationPath()
                        path.append(plan)
                        GlobalRouter.shared.planNavigationPath = path
                        GlobalRouter.shared.activeTab = 3
                    }) {
                        HStack {
                            Image(systemName: "checklist")
                            Text("Prepare & Checklist")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                
                // Walk: tracking shows live stats + Finish anywhere on the route.
                if viewModel.isTrackingWalk {
                    walkTrackingSection(route: route)
                } else if viewModel.isAtTrailhead {
                    Button(action: {
                        withAnimation { viewModel.beginTrackingWalk() }
                    }) {
                        HStack {
                            Image(systemName: "figure.walk")
                            Text("Start Walk")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                } else {
                    Button(action: {
                        let location = CLLocation(latitude: route.startingCoordinate.latitude, longitude: route.startingCoordinate.longitude)
                        let mapItem = MKMapItem(location: location, address: nil)
                        mapItem.name = "\(route.name) (Trailhead)"
                        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    }) {
                        Text("Directions to Start")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        // THE NATIVE FIX: Replaced .ultraThinMaterial with solid system background
        .background(Color(UIColor.systemBackground))
        .cornerRadius(24)
        // Adjusted shadow for a tighter native iOS feel
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    private func walkTrackingSection(route: TrekRoute) -> some View {
        let progress = viewModel.walkProgress
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    walkStatsMinimized.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: walkStatsMinimized ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(walkStatsMinimized ? "Show walk stats" : "Minimize stats")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if !walkStatsMinimized {
                if let p = progress {
                    VStack(alignment: .leading, spacing: 10) {
                        if (route.routeCoordinates?.count ?? 0) > 1, p.distanceFromPathMeters > 120 {
                            Label("You may be off the plotted path (~\(Int(p.distanceFromPathMeters)) m)", systemImage: "location.slash")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        
                        if let n = route.routeCoordinates?.count, n > 1, p.nextVertexIndex < n {
                            Text("Next checkpoint: \(p.nextVertexIndex + 1) of \(n)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        WalkStatLine(title: "To next checkpoint", value: "\(p.formattedDistanceKm(p.distanceAlongPathToNextVertexMeters)) · ~\(p.formattedMinutes(p.etaNextVertexSeconds))")
                        WalkStatLine(title: "Remaining (along route)", value: "\(p.formattedDistanceKm(p.distanceRemainingMeters)) · ~\(p.formattedMinutes(p.etaRemainingSeconds))")
                        WalkStatLine(title: "Covered", value: p.formattedDistanceKm(p.distanceCoveredMeters))
                        
                        if let diff = viewModel.upcomingSegmentCondition(route: route, progress: p) {
                            WalkStatLine(title: "Difficulty ahead", value: diff)
                        } else if let overall = route.difficultyRating?.trimmingCharacters(in: .whitespacesAndNewlines), !overall.isEmpty {
                            WalkStatLine(title: "Route difficulty", value: overall)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                } else {
                    Text("Waiting for GPS…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                }
            } else if let p = progress {
                HStack(spacing: 8) {
                    Text("Next ~\(p.formattedMinutes(p.etaNextVertexSeconds))")
                        .font(.caption.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(p.formattedDistanceKm(p.distanceRemainingMeters)) left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            
            Button(action: {
                viewModel.requestManualWalkEnd()
            }) {
                HStack {
                    Image(systemName: "flag.checkered.circle.fill")
                    Text("Finish Walk")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private func buildWalkCompletionCard(_ summary: WalkCompletionSummary) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "flag.checkered.circle.fill")
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text(summary.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(summary.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    viewModel.confirmWalkCompletion(navigateToProfile: true)
                } label: {
                    Text("View profile")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                Button {
                    viewModel.confirmWalkCompletion(navigateToProfile: false)
                } label: {
                    Text("Stay on map")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    private func buildNearbyRoutesDrawer() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                
                HStack {
                    Text("Nearby Routes")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                        .font(.system(size: 22))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded List
            if isExpanded {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(viewModel.nearbyRoutes) { route in
                            Button {
                                viewModel.focusOnRoute(route)
                                withAnimation { isExpanded = false }
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(route.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(route.summary)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Label {
                                        Text(String(format: "%.1f km total", route.distance))
                                            .font(.footnote)
                                            .fontWeight(.medium)
                                    } icon: {
                                        Image(systemName: "figure.walk")
                                            .font(.footnote)
                                    }
                                    .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .frame(height: 280)
            }
        }
        // THE NATIVE FIX: Replaced .ultraThinMaterial with solid system background
        .background(Color(UIColor.systemBackground))
        .cornerRadius(24)
        // Adjusted shadow for a tighter native iOS feel
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private func strokeSegmentsForMap(route: TrekRoute, coords: [CoordinatePoint]) -> [(coordinates: [CLLocationCoordinate2D], color: Color)] {
        if viewModel.isTrackingWalk,
           let p = viewModel.walkProgress,
           let seg = p.trimLeadingSegmentIndex {
            return RoutePolylineStyle.strokeSegmentsRemaining(
                coords: coords,
                leadingSegmentIndex: seg,
                leadingT: p.trimLeadingSegmentT
            )
        }
        return RoutePolylineStyle.strokeSegments(for: route)
    }
    
    // MARK: - Helper Methods
    
    // Maps the internal string representation to an SF Symbol
    private func iconForActivity(_ activity: String?) -> String {
        switch activity {
        case "Cycling": return "bicycle"
        case "Mountain Biking": return "bicycle"
        case "Equestrian": return "figure.equestrian.sports"
        default: return "figure.walk" // Fallback to hiking
        }
    }
}

private struct WalkStatLine: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
