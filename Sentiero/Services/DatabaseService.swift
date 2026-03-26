import Foundation
import FirebaseFirestore

final class DatabaseService {
    static let shared = DatabaseService()

    private let db = Firestore.firestore()
    private var cachedPublicRoutes: [TrekRoute]?

    func fetchPublicRoutes(completion: @escaping ([TrekRoute]) -> Void) {
        if let cached = cachedPublicRoutes {
            completion(cached)
            return
        }

        db.collection("public_routes").getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("Database Error: \(error.localizedDescription)")
                completion([])
                return
            }

            guard let documents = snapshot?.documents else {
                print("No documents found in public_routes.")
                completion([])
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let routes: [TrekRoute] = documents.compactMap { doc in
                    Self.decodePublicRouteDocument(doc)
                }

                print("Successfully fetched and decoded \(routes.count) public routes from public_routes.")

                DispatchQueue.main.async {
                    self?.cachedPublicRoutes = routes
                    completion(routes)
                }
            }
        }
    }

    func invalidatePublicRoutesCache() {
        cachedPublicRoutes = nil
    }
    
    /// After Gemini enriches a public route with per-segment conditions, keep the in-memory catalog in sync.
    func mergeEnrichedRouteIntoCache(_ route: TrekRoute) {
        guard var list = cachedPublicRoutes else { return }
        if let i = list.firstIndex(where: { $0.id == route.id }) {
            list[i] = route
            cachedPublicRoutes = list
        }
    }

    /// Manual decode only (avoids Swift 6 / main-actor issues with `doc.data(as: TrekRoute.self)`).
    private nonisolated static func decodePublicRouteDocument(_ doc: QueryDocumentSnapshot) -> TrekRoute? {
        let data = doc.data()
        let distance = (data["distance"] as? Double) ?? (data["distance"] as? NSNumber)?.doubleValue
        guard let name = data["name"] as? String,
              let distance else {
            print("Error parsing document (missing name/distance): \(doc.documentID)")
            return nil
        }

        let summary = data["summary"] as? String ?? ""
        let difficultyRating = data["difficultyRating"] as? String
        let activityType = data["activityType"] as? String

        let coords = FirestoreCoordinateParsing.parseCoordinateArray(from: data)

        let startLat = (data["startLatitude"] as? Double)
            ?? (data["startLatitude"] as? NSNumber)?.doubleValue
            ?? coords?.first?.latitude
            ?? 0.0
        let startLon = (data["startLongitude"] as? Double)
            ?? (data["startLongitude"] as? NSNumber)?.doubleValue
            ?? coords?.first?.longitude
            ?? 0.0

        return TrekRoute(
            id: doc.documentID,
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
