import SwiftUI
import MapKit

struct RoutesListView: View {
    @StateObject private var viewModel = RoutesListViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // 1. The Native iOS Segmented Control
                Picker("Route Type", selection: $viewModel.selectedTab) {
                    Text("Public Routes").tag(RoutesListViewModel.RouteTab.publicRoutes)
                    Text("Saved AI Routes").tag(RoutesListViewModel.RouteTab.savedRoutes)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(UIColor.systemBackground))
                
                // 2. The Native iOS List Engine
                List {
                    if viewModel.selectedTab == .publicRoutes {
                        if viewModel.filteredPublicRoutes.isEmpty {
                            Text("No routes match your search or filters.")
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(viewModel.filteredPublicRoutes) { route in
                                buildNativeRouteRow(route)
                            }
                        }
                    } else {
                        if viewModel.filteredSavedRoutes.isEmpty {
                            buildNativeEmptyState()
                        } else {
                            ForEach(viewModel.filteredSavedRoutes) { route in
                                buildNativeRouteRow(route)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped) // Apple's standard grouped aesthetic
            }
            .navigationTitle("Route Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Activity Filter
                        Picker("Activity", selection: $viewModel.selectedActivity) {
                            Text("All Activities").tag(String?.none)
                            ForEach(viewModel.activityTypes, id: \.self) { activity in
                                Text(activity).tag(String?(activity))
                            }
                        }
                        
                        // Difficulty Filter
                        Picker("Difficulty", selection: $viewModel.selectedDifficulty) {
                            Text("All Difficulties").tag(String?.none)
                            ForEach(viewModel.difficulties, id: \.self) { difficulty in
                                Text(difficulty).tag(String?(difficulty))
                            }
                        }
                        
                        // Clear Filters
                        if viewModel.selectedActivity != nil || viewModel.selectedDifficulty != nil {
                            Button(role: .destructive, action: {
                                viewModel.selectedActivity = nil
                                viewModel.selectedDifficulty = nil
                            }) {
                                Label("Clear Filters", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.selectedActivity != nil || viewModel.selectedDifficulty != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            // 3. Apple's native search bar — it auto-hides when scrolling!
            .searchable(text: $viewModel.searchText, prompt: "Search by name or location...")
            .onAppear {
                viewModel.fetchSavedRoutes()
                viewModel.refreshPublicRoutes()
            }
        }
    }
    
    // MARK: - Native UI Components
    
    @ViewBuilder
    private func buildNativeRouteRow(_ route: TrekRoute) -> some View {
        Button(action: {
            // Commands the global nervous system to open the map and focus the route
            GlobalRouter.shared.routeToFocusOnMap = route
            GlobalRouter.shared.activeTab = 0
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: iconForActivity(route.activityType))
                        .foregroundColor(.blue)
                        .frame(width: 20, alignment: .center)
                    
                    Text(route.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text(route.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Label(String(format: "%.1f km", route.distance), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    if let diff = route.difficultyRating {
                        Text(diff)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                            .padding(.trailing, 4)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain) // Prevents the entire row's text from turning blue
    }
    
    // Maps the internal string representation to an SF Symbol
    private func iconForActivity(_ activity: String?) -> String {
        switch activity {
        case "Cycling": return "bicycle"
        case "Mountain Biking": return "bicycle" // The standard bicycle looks reasonably rugged enough in standard SF UI
        case "Equestrian": return "figure.equestrian.sports"
        default: return "figure.walk" // Fallback to hiking
        }
    }
    
    @ViewBuilder
    private func buildNativeEmptyState() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Saved AI Routes")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Routes you generate and save from the AI map will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear) // Removes the white box so it blends with the background
    }
}
