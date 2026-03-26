//
//  CloudPlanManager.swift
//  Sentiero
//
//  Created by Nirav Tailor on 26/02/2026.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore

class CloudPlanManager {
    static let shared = CloudPlanManager()
    private let db = Firestore.firestore()
    
    func savePlan(_ plan: RoutePlan) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("CloudPlanManager: no Firebase user — plan kept local only. Sign in to sync plans.")
            return
        }
        
        let docRef = db.collection("users").document(uid).collection("activePlans").document(plan.id)
        
        do {
            try docRef.setData(from: plan)
            print("CloudPlanManager: synced plan \(plan.id) to Firestore.")
        } catch {
            print("CloudPlanManager PLAN SYNC ERROR: \(error.localizedDescription)")
        }
    }
    
    func fetchPlans() async throws -> [RoutePlan] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        
        let snapshot = try await db.collection("users").document(uid).collection("activePlans").getDocuments()
        
        return snapshot.documents.compactMap { doc in
            do {
                return try doc.data(as: RoutePlan.self)
            } catch {
                print("CloudPlanManager: decode failed for \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    func deletePlan(id: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("activePlans").document(id).delete { error in
            if let error = error {
                print("CloudPlanManager: delete error \(error.localizedDescription)")
            }
        }
    }
}
