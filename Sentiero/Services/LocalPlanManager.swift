//
//  LocalPlanManager.swift
//  Sentiero
//
//  Created by Nirav Tailor on 26/02/2026.
//


import Foundation
import FirebaseAuth

class LocalPlanManager {
    static let shared = LocalPlanManager()

    private func plansStorageKey() -> String? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return nil }
        return "user_route_plans.\(uid)"
    }
    
    func getPlans() -> [RoutePlan] {
        guard let key = plansStorageKey() else { return [] }
        guard let data = UserDefaults.standard.data(forKey: key),
              let plans = try? JSONDecoder().decode([RoutePlan].self, from: data) else {
            return []
        }
        return plans
    }

    /// Most recently stored plan whose `route.id` matches (newest-first list order wins if several exist).
    func existingPlan(forRouteId routeId: String) -> RoutePlan? {
        getPlans().first { $0.route.id == routeId }
    }
    
    func savePlan(_ plan: RoutePlan) {
        guard let key = plansStorageKey() else {
            CloudPlanManager.shared.savePlan(plan)
            return
        }
        var currentPlans = getPlans()
        if let index = currentPlans.firstIndex(where: { $0.id == plan.id }) {
            currentPlans[index] = plan // Update existing
        } else {
            currentPlans.insert(plan, at: 0) // Add new to the top
        }
        
        if let encoded = try? JSONEncoder().encode(currentPlans) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        CloudPlanManager.shared.savePlan(plan)
    }
    
    func deletePlan(id: String) {
        guard let key = plansStorageKey() else {
            CloudPlanManager.shared.deletePlan(id: id)
            return
        }
        var currentPlans = getPlans()
        currentPlans.removeAll { $0.id == id }
        if let encoded = try? JSONEncoder().encode(currentPlans) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        CloudPlanManager.shared.deletePlan(id: id)
    }
}
