import SwiftUI
import MapKit

struct ActivePlanHubView: View {
    /// Singleton router must use `ObservedObject` so `@Published` updates (e.g. path) refresh this tab reliably.
    @ObservedObject private var router = GlobalRouter.shared
    @State private var savedPlans: [RoutePlan] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack(path: $router.planNavigationPath) {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing with Cloud...").font(.caption).foregroundColor(.secondary)
                    }
                } else if savedPlans.isEmpty {
                    buildNativeEmptyState()
                } else {
                    List {
                        ForEach(savedPlans) { plan in
                            NavigationLink(value: plan) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.displayTitle)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    let completed = plan.checklist.filter { $0.isCompleted }.count
                                    let total = plan.checklist.count
                                    
                                    Text("\(completed) of \(total) items prepared")
                                        .font(.caption)
                                        .foregroundColor(completed == total && total > 0 ? .green : .secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deletePlan)
                    }
                }
            }
            .navigationTitle("My Route Plans")
            .onAppear {
                loadCloudPlans()
            }
            .navigationDestination(for: RoutePlan.self) { selectedPlan in
                // New plan on the path must rebuild VM/state; otherwise @StateObject keeps the previous checklist.
                ActiveChecklistInterface(plan: selectedPlan)
                    .id(selectedPlan.id)
            }
        }
        .id(router.planHubStackIdentity)
    }
    
    private func loadCloudPlans() {
        isLoading = true
        Task {
            do {
                var cloudPlans = try await CloudPlanManager.shared.fetchPlans()
                let localPlans = LocalPlanManager.shared.getPlans()
                var byId = Dictionary(uniqueKeysWithValues: cloudPlans.map { ($0.id, $0) })
                for local in localPlans {
                    if let cloud = byId[local.id] {
                        if local.checklist.count > cloud.checklist.count {
                            CloudPlanManager.shared.savePlan(local)
                            byId[local.id] = local
                        }
                    } else {
                        CloudPlanManager.shared.savePlan(local)
                        byId[local.id] = local
                    }
                }
                cloudPlans = Array(byId.values).sorted {
                    $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                await MainActor.run {
                    self.savedPlans = cloudPlans
                    self.isLoading = false
                }
            } catch {
                print("Failed to load cloud plans: \(error.localizedDescription)")
                let localOnly = LocalPlanManager.shared.getPlans()
                await MainActor.run {
                    self.savedPlans = localOnly
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deletePlan(at offsets: IndexSet) {
        for index in offsets {
            LocalPlanManager.shared.deletePlan(id: savedPlans[index].id)
        }
        savedPlans.remove(atOffsets: offsets)
    }
    
    @ViewBuilder
    private func buildNativeEmptyState() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Saved Plans")
                .font(.title3)
                .fontWeight(.bold)
            
            Text("Find a route on the map and tap 'Prepare & Checklist' to start preparing for your hike.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Subviews

struct ActiveChecklistInterface: View {
    @StateObject private var viewModel: RoutePlanViewModel
    @State private var showRenameSheet = false
    @State private var renameDraft = ""

    init(plan: RoutePlan) {
        _viewModel = StateObject(wrappedValue: RoutePlanViewModel(plan: plan))
    }

    private func openOnMapAndSwitchTab() {
        GlobalRouter.shared.routeToFocusOnMap = viewModel.plan.route
        GlobalRouter.shared.activeTab = 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                buildRouteHeader()

                Button(action: openOnMapAndSwitchTab) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Start route on map")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Preparation Checklist")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    if viewModel.isGeneratingChecklist {
                        VStack(spacing: 16) {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .blue)).scaleEffect(1.5)
                            Text("AI generating initial checklist...").font(.subheadline).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                        .background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12).padding(.horizontal)
                    } else {
                        ForEach(viewModel.categoryDisplayOrder, id: \.self) { category in
                            if let items = viewModel.groupedChecklist[category], !items.isEmpty {
                                buildChecklistSection(title: category, items: items)
                            }
                        }
                    }
                }
                Spacer().frame(height: 100)
            }
            .padding(.top, 16)
        }
        .navigationTitle(viewModel.plan.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        openOnMapAndSwitchTab()
                    } label: {
                        Label("Start route on map", systemImage: "map")
                    }
                    Button {
                        renameDraft = viewModel.plan.displayTitle
                        showRenameSheet = true
                    } label: {
                        Label("Rename plan", systemImage: "pencil")
                    }
                    Divider()
                    Button("Customize Route") {
                        viewModel.enterRouteEditing()
                    }
                    .disabled(viewModel.isEditingRoute)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                Form {
                    TextField("Plan name", text: $renameDraft)
                }
                .navigationTitle("Rename plan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            viewModel.setPlanDisplayTitle(renameDraft)
                            showRenameSheet = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.isEditingRoute },
            set: { newValue in
                if !newValue { viewModel.cancelRouteEditing() }
            }
        )) {
            RouteFullScreenEditView(viewModel: viewModel)
        }
    }
    
    @ViewBuilder
    private func buildRouteHeader() -> some View {
        VStack(spacing: 0) {
            Map(interactionModes: []) {
                if let coords = viewModel.plan.route.routeCoordinates, coords.count > 1 {
                    let segments = RoutePolylineStyle.strokeSegments(for: viewModel.plan.route)
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        MapPolyline(coordinates: seg.coordinates)
                            .stroke(seg.color, style: RoutePolylineStyle.lineStyleCompact)
                    }
                    
                    if let start = coords.first {
                        Marker("Start", systemImage: iconForActivity(viewModel.plan.route.activityType), coordinate: start.asCLLocationCoordinate).tint(.green)
                    }
                } else {
                    Marker(viewModel.plan.route.name, systemImage: iconForActivity(viewModel.plan.route.activityType), coordinate: viewModel.plan.route.startingCoordinate).tint(.blue)
                }
            }
            .frame(height: 200)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.plan.displayTitle).font(.title2).fontWeight(.bold)
                Text(viewModel.plan.route.summary).font(.body).foregroundColor(.secondary)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(UIColor.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    // Maps the internal string representation to an SF Symbol
    private func iconForActivity(_ activity: String?) -> String {
        switch activity {
        case "Cycling": return "bicycle"
        case "Mountain Biking": return "bicycle"
        case "Equestrian": return "figure.equestrian.sports"
        default: return "figure.walk" // Fallback to hiking
        }
    }
    
    @ViewBuilder
    private func buildChecklistSection(title: String, items: [ChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.caption).fontWeight(.bold).foregroundColor(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.toggleItem(id: item.id) }
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle").font(.title2).foregroundColor(item.isCompleted ? .green : .secondary.opacity(0.5)).scaleEffect(item.isCompleted ? 1.1 : 1.0)
                            Text(item.title).font(.body).foregroundColor(item.isCompleted ? .secondary : .primary).strikethrough(item.isCompleted)
                            Spacer()
                        }
                        .padding(.vertical, 14).padding(.horizontal, 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if index < items.count - 1 { Divider().padding(.leading, 50) }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12).padding(.horizontal)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Full-screen route editor

private struct RouteFullScreenEditView: View {
    @ObservedObject var viewModel: RoutePlanViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                CustomEditMapView(
                    waypoints: $viewModel.editWaypoints,
                    displayPolyline: viewModel.editDisplayPolyline,
                    mapFitToken: viewModel.routeEditMapFitToken,
                    onWaypointCommit: { viewModel.schedulePolylineRecalculation() }
                )
                .ignoresSafeArea(edges: .all)

                if viewModel.isRecalculatingRoute {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.35)
                        Text("Recalculating route…")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Snapping to walking paths")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(28)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.94))
                    }
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                }
            }
            .navigationTitle(viewModel.plan.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelRouteEditing()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        viewModel.saveEditedRoute()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isRecalculatingRoute || viewModel.editWaypoints.count < 2)
                }
            }
        }
    }
}
