import SwiftUI

struct MainTabView: View {
    // 1. Shared router — ObservedObject so updates from any screen (e.g. map → Plan) refresh tab selection.
    @ObservedObject private var router = GlobalRouter.shared
    
    var body: some View {
        // 2. Bind the selection to the engine
        TabView(selection: $router.activeTab) {
            HomeMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(0) // Mathematical Index 0
            
            AIGeneratedRouteView()
                .tabItem { Label("AI Route", systemImage: "sparkles") }
                .tag(1) // Mathematical Index 1
            
            RoutesListView()
                .tabItem { Label("Routes", systemImage: "list.bullet") }
                .tag(2) // Mathematical Index 2
            
            // Temporary placeholder for our future Plan Hub
            ActivePlanHubView()
                .tabItem { Label("Plan", systemImage: "checklist") }
                .tag(3) // Mathematical Index 3
            
            UserProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4) // Mathematical Index 4
        }
    }
}
