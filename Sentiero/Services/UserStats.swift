//
//  UserStats.swift
//  Sentiero
//
//  Created by Nirav Tailor on 26/02/2026.
//


import Foundation
import FirebaseAuth

// 1. The strict mathematical blueprint for user data
struct UserStats: Codable {
    var completedRoutes: Int = 0
    var totalDistanceKM: Double = 0.0
}

class LocalProfileManager {
    static let shared = LocalProfileManager()

    private func statsStorageKey() -> String? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return nil }
        return "user_hiking_stats.\(uid)"
    }
    
    // 2. The Retrieval Command
    func getStats() -> UserStats {
        guard let key = statsStorageKey() else { return UserStats() }
        if let data = UserDefaults.standard.data(forKey: key),
           let stats = try? JSONDecoder().decode(UserStats.self, from: data) {
            return stats
        }
        return UserStats() // Returns baseline 0.0 if no data exists yet
    }
    
    // 3. The Mathematical Update Command
    func addCompletedRoute(distance: Double) {
        guard let key = statsStorageKey() else { return }
        var currentStats = getStats()
        
        // Increment the physical logic
        currentStats.completedRoutes += 1
        currentStats.totalDistanceKM += distance
        
        // Compress and write back to the hard drive
        if let encoded = try? JSONEncoder().encode(currentStats) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func resetStats() {
        guard let key = statsStorageKey() else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }
}