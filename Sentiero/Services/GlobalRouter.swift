import Foundation
import Combine
import SwiftUI

class GlobalRouter: ObservableObject {
    static let shared = GlobalRouter()
    
    @Published var activeTab: Int = 0
    @Published var routeToFocusOnMap: TrekRoute? = nil
    @Published var planNavigationPath = NavigationPath()
    /// Bumping this recreates the Plan tab `NavigationStack` so a new checklist is not confused with the previous one.
    @Published private(set) var planHubStackIdentity = UUID()

    private init() {}

    /// Replace the plan navigation stack and switch to Plan. Use this from the map so the correct checklist always appears.
    func openPrepareAndChecklist(plan: RoutePlan) {
        planHubStackIdentity = UUID()
        var path = NavigationPath()
        path.append(plan)
        planNavigationPath = path
        activeTab = 3
    }

    /// Call when the Firebase account changes or signs out so another user never inherits navigation or map focus.
    func resetForAccountChange() {
        planHubStackIdentity = UUID()
        planNavigationPath = NavigationPath()
        routeToFocusOnMap = nil
        activeTab = 0
    }
}
