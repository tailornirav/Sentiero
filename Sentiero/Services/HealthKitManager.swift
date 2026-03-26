import Foundation
import HealthKit

/// Writes completed hikes to Apple Health as workouts when the user has granted permission.
final class HealthKitManager: @unchecked Sendable {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    private init() {}

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func workoutSharingStatus() -> HKAuthorizationStatus {
        store.authorizationStatus(for: HKObjectType.workoutType())
    }

    /// Requests permission to save hiking workouts. Call from an explicit user action.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { return }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
    }

    /// Saves a hiking workout if Health is available and write access was granted.
    func saveHikingWorkout(routeName: String, start: Date, end: Date, distanceMeters: Double) async {
        guard isHealthDataAvailable else { return }
        guard workoutSharingStatus() == .sharingAuthorized else { return }
        guard distanceMeters >= 5, end > start else { return }

        let duration = end.timeIntervalSince(start)
        guard duration >= 1 else { return }

        let totalDistance = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
        let workout = HKWorkout(
            activityType: .hiking,
            start: start,
            end: end,
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: totalDistance,
            metadata: [
                HKMetadataKeyWorkoutBrandName: "Sentiero",
                "SentieroRouteName": routeName
            ]
        )

        do {
            try await store.save(workout)
        } catch {
            #if DEBUG
            print("HealthKitManager: save workout failed — \(error.localizedDescription)")
            #endif
        }
    }
}
