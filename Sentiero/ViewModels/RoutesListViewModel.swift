import Foundation
import Combine

@MainActor
class RoutesListViewModel: ObservableObject {
    @Published var allPublicRoutes: [TrekRoute] = []
    
    // NEW: Array to hold the routes fetched from the hard drive
    @Published var savedAIRoutes: [TrekRoute] = []
    
    @Published var searchText: String = ""
    @Published var selectedTab: RouteTab = .publicRoutes
    
    // NEW: Filter criteria
    @Published var selectedActivity: String? = nil
    @Published var selectedDifficulty: String? = nil
    
    let activityTypes = ["Hiking", "Cycling", "Mountain Biking", "Equestrian"]
    let difficulties = ["Easy", "Moderate", "Hard"]
    
    enum RouteTab {
        case publicRoutes
        case savedRoutes
    }
    
    init() {
        refreshPublicRoutes()
    }
    
    private func fetchPublicRoutes() {
        DatabaseService.shared.fetchPublicRoutes { [weak self] routes in
            DispatchQueue.main.async { self?.allPublicRoutes = routes.sorted { $0.name < $1.name } }
        }
    }

    func refreshPublicRoutes() {
        fetchPublicRoutes()
    }
    
    func fetchSavedRoutes() {
            Task {
                do {
                    let cloudRoutes = try await CloudRouteManager.shared.fetchSavedRoutes()
                    
                    DispatchQueue.main.async {
                        self.savedAIRoutes = cloudRoutes
                    }
                } catch {
                    print("Failed to download routes from cloud: \(error.localizedDescription)")
                }
            }
        }
    
    var filteredPublicRoutes: [TrekRoute] {
        var routes = allPublicRoutes
        
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            routes = routes.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.summary.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let diff = selectedDifficulty {
            routes = routes.filter { $0.difficultyRating == diff }
        }
        
        if let activity = selectedActivity {
            routes = routes.filter { ($0.activityType ?? "Hiking") == activity }
        }
        
        return routes
    }
    
    // NEW: Search logic applied to the saved routes
    var filteredSavedRoutes: [TrekRoute] {
        var routes = savedAIRoutes
        
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            routes = routes.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.summary.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let diff = selectedDifficulty {
            routes = routes.filter { $0.difficultyRating == diff }
        }
        
        if let activity = selectedActivity {
            routes = routes.filter { ($0.activityType ?? "Hiking") == activity }
        }
        
        return routes
    }
}
