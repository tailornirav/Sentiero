import SwiftUI

struct ProfilePreferencesView: View {
    @AppStorage(ProfileSettings.useMetricUnitsKey) private var useMetricUnits: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Use metric units", isOn: $useMetricUnits)
            } footer: {
                Text("Distances on your profile use kilometers or miles based on this setting.")
            }
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
