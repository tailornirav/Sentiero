import SwiftUI
import UIKit
import FirebaseAuth
import HealthKit

struct UserProfileView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var authManager = AuthManager.shared
    @State private var stats: UserStats = UserStats()
    @AppStorage(ProfileSettings.useMetricUnitsKey) private var useMetricUnits: Bool = true

    @State private var healthShareStatus: HKAuthorizationStatus = .notDetermined
    @State private var healthRequestInFlight = false
    @State private var healthMessage: String?

    @State private var showClearCacheConfirm = false
    @State private var showResetStatsConfirm = false

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {
                identitySection
                statsSection
                healthSection
                settingsSection
                dataSection
                aboutSection
                signOutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .onAppear {
                stats = LocalProfileManager.shared.getStats()
                refreshHealthStatus()
            }
            .onChange(of: authManager.isAuthenticated) { _, _ in
                stats = LocalProfileManager.shared.getStats()
            }
            .confirmationDialog(
                "Clear the in-memory catalog of public routes?",
                isPresented: $showClearCacheConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear cache", role: .destructive) {
                    DatabaseService.shared.invalidatePublicRoutesCache()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The next map load will fetch fresh routes from the server. Your plans and saved routes stay on this device.")
            }
            .confirmationDialog(
                "Reset hiking stats on this device?",
                isPresented: $showResetStatsConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset stats", role: .destructive) {
                    LocalProfileManager.shared.resetStats()
                    stats = LocalProfileManager.shared.getStats()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Completed route count and total distance stored in Sentiero will be set to zero. This does not change Apple Health.")
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text(accountTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(accountSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var statsSection: some View {
        Section("My hiking stats") {
            HStack {
                Text("Completed routes")
                Spacer()
                Text("\(stats.completedRoutes)")
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Distance walked")
                Spacer()
                Text(formattedTotalDistance)
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section {
            if HealthKitManager.shared.isHealthDataAvailable {
                VStack(alignment: .leading, spacing: 12) {
                    Text("When you finish a walk in Sentiero, we can add a hiking workout to Apple Health using the time you were tracking and the distance you covered along the route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let healthMessage {
                        Text(healthMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    switch healthShareStatus {
                    case .sharingAuthorized:
                        Label("Workouts will save to Health", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    case .sharingDenied:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Health access is off. Turn on “Workouts” write access for Sentiero in Settings → Apps → Health → Data Access.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    default:
                        Button {
                            Task { await requestHealthAccess() }
                        } label: {
                            if healthRequestInFlight {
                                HStack {
                                    ProgressView()
                                    Text("Connecting…")
                                }
                            } else {
                                Label("Connect Apple Health", systemImage: "heart.circle.fill")
                            }
                        }
                        .disabled(healthRequestInFlight)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Apple Health isn’t available on this device.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Health")
        }
    }

    private var settingsSection: some View {
        Section("Settings") {
            NavigationLink {
                ProfilePreferencesView()
            } label: {
                Label("Preferences", systemImage: "gear")
            }
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                showClearCacheConfirm = true
            } label: {
                Label("Clear public routes cache", systemImage: "arrow.counterclockwise.circle")
            }

            Button(role: .destructive) {
                showResetStatsConfirm = true
            } label: {
                Label("Reset local hiking stats", systemImage: "arrow.uturn.backward.circle")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Clearing cache only refreshes the public route list from the server. Resetting stats clears counts stored in Sentiero, not your Health history.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                AuthManager.shared.signOut()
            } label: {
                HStack {
                    Spacer()
                    Text("Sign out")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Account copy

    private var accountTitle: String {
        guard let user = Auth.auth().currentUser else { return "Explorer" }
        if user.isAnonymous {
            return "Guest"
        }
        if let email = user.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }
        if let name = user.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Apple account"
    }

    private var accountSubtitle: String {
        guard let user = Auth.auth().currentUser else {
            return "Not signed in"
        }
        if user.isAnonymous {
            return "Use Sign in with Apple on the welcome screen to sync routes and plans."
        }
        return "Signed in — routes and plans can sync to your account."
    }

    private var formattedTotalDistance: String {
        let km = stats.totalDistanceKM
        if useMetricUnits {
            return String(format: "%.1f km", km)
        }
        let miles = km * 0.621_371
        return String(format: "%.1f mi", miles)
    }

    private func refreshHealthStatus() {
        guard HealthKitManager.shared.isHealthDataAvailable else {
            healthShareStatus = .notDetermined
            return
        }
        healthShareStatus = HealthKitManager.shared.workoutSharingStatus()
    }

    private func requestHealthAccess() async {
        healthRequestInFlight = true
        healthMessage = nil
        defer { healthRequestInFlight = false }
        do {
            try await HealthKitManager.shared.requestAuthorization()
            refreshHealthStatus()
            if healthShareStatus != .sharingAuthorized {
                healthMessage = "If the sheet appeared, choose “Allow” so Sentiero can save workouts."
            }
        } catch {
            healthMessage = error.localizedDescription
        }
    }
}
