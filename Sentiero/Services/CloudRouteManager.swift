import Foundation
import FirebaseFirestore

class CloudRouteManager {
    static let shared = CloudRouteManager()
    
    // 1. Initialize the strict connection to the cloud database
    private let db = Firestore.firestore()
    
    // 2. The Cloud Write Command
    func saveRoute(_ route: TrekRoute) {
        // Mathematically ensure we have a secure user ID before writing
        guard let uid = AuthManager.shared.currentUserID else {
            print("ERROR: Cannot save route without an authenticated UID.")
            return
        }
        
        // Define the strict NoSQL path
        let docRef = db.collection("users").document(uid).collection("savedRoutes").document(route.id)
        
        do {
            // Because TrekRoute is already Codable, Firestore can automatically compress it into JSON
            try docRef.setData(from: route)
            print("SUCCESS: Route perfectly written to Firestore Cloud.")
        } catch {
            print("FIRESTORE WRITE ERROR: \(error.localizedDescription)")
        }
    }
    
    // 3. The Cloud Read Command (Asynchronous)
    func fetchSavedRoutes() async throws -> [TrekRoute] {
        guard let uid = AuthManager.shared.currentUserID else { return [] }
        
        let snapshot = try await db.collection("users").document(uid).collection("savedRoutes").getDocuments()
        
        return snapshot.documents.compactMap { document in
            // Try strict Codable decode first
            if let decoded = try? document.data(as: TrekRoute.self) {
                return decoded
            }
            
            // Fallback decoder
            let data = document.data()
            let distance = (data["distance"] as? Double) ?? (data["distance"] as? NSNumber)?.doubleValue
            let startLat = (data["startLatitude"] as? Double) ?? (data["startLatitude"] as? NSNumber)?.doubleValue
            let startLon = (data["startLongitude"] as? Double) ?? (data["startLongitude"] as? NSNumber)?.doubleValue
            guard let name = data["name"] as? String,
                  let distance,
                  let startLat,
                  let startLon else {
                print("CloudRouteManager: Error parsing document: \(document.documentID)")
                return nil
            }
            
            let summary = data["summary"] as? String ?? ""
            let difficultyRating = data["difficultyRating"] as? String
            let activityType = data["activityType"] as? String
            let coords = FirestoreCoordinateParsing.parseCoordinateArray(from: data)

            return TrekRoute(
                id: document.documentID,
                name: name,
                summary: summary,
                distance: distance,
                startLatitude: startLat,
                startLongitude: startLon,
                weatherSummary: data["weatherSummary"] as? String,
                estimatedDuration: data["estimatedDuration"] as? String,
                difficultyRating: difficultyRating,
                activityType: activityType ?? "Hiking",
                routeCoordinates: coords
            )
        }
    }
    
    // 4. The Cloud Delete Command
    func deleteRoute(id: String) {
        guard let uid = AuthManager.shared.currentUserID else { return }
        db.collection("users").document(uid).collection("savedRoutes").document(id).delete()
    }
}
