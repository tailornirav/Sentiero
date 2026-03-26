import Foundation

class LocalRouteManager {
    // 1. Singleton pattern ensures only one memory pipeline exists
    static let shared = LocalRouteManager()
    
    // The strict key used to locate the data on the device's hard drive
    private let savedRoutesKey = "saved_ai_routes"
    
    // 2. The Save Function
    func saveRoute(_ route: TrekRoute) {
        var currentRoutes = getSavedRoutes()
        
        // Prevent saving the exact same route twice
        if !currentRoutes.contains(where: { $0.id == route.id }) {
            currentRoutes.append(route)
            
            // Mathematically compress the Swift object into raw JSON data
            if let encodedData = try? JSONEncoder().encode(currentRoutes) {
                UserDefaults.standard.set(encodedData, forKey: savedRoutesKey)
            }
        }
    }
    
    // 3. The Retrieval Function
    func getSavedRoutes() -> [TrekRoute] {
        // Unpack the raw JSON data back into strict Swift objects
        if let data = UserDefaults.standard.data(forKey: savedRoutesKey),
           let routes = try? JSONDecoder().decode([TrekRoute].self, from: data) {
            return routes
        }
        return [] // Return an empty array if nothing is saved yet
    }
}
