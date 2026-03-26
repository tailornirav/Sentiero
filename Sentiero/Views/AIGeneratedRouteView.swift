import SwiftUI
import MapKit

struct AIGeneratedRouteView: View {
    @StateObject private var viewModel = AIGeneratedRouteViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.large) {
                        
                        // --- 1. HEADER (Only show when not generating and no route) ---
                        if viewModel.generatedRoute == nil && !viewModel.isGenerating {
                            VStack(spacing: Theme.Spacing.small) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 60))
                                    .foregroundColor(Theme.Colors.primary)
                                    .padding(.bottom, Theme.Spacing.small)
                                
                                Text("Dream up a trail.")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                
                                Text("Tell Sentiero what kind of adventure you want. We'll handle the topography, weather, and routing.")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Theme.Spacing.medium)
                            }
                            .padding(.top, Theme.Spacing.xlarge)
                        }
                        
                        // --- 2. INPUT SECTION ---
                        VStack(spacing: Theme.Spacing.medium) {
                            TextField("E.g., A 5km coastal walk nearby...", text: $viewModel.prompt, axis: .vertical)
                                .lineLimit(1...4)
                                .standardTextField()
                                .disabled(viewModel.isGenerating || viewModel.generatedRoute != nil)
                            
                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, Theme.Spacing.medium)
                                    .padding(.vertical, Theme.Spacing.small)
                                    .background(Color.red.opacity(0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard, style: .continuous))
                            }
                            
                            if viewModel.generatedRoute == nil {
                                Button(action: { viewModel.submitPrompt() }) {
                                    if viewModel.isGenerating {
                                        HStack(spacing: Theme.Spacing.small) {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            Text("Crafting Adventure...")
                                                .fontWeight(.bold)
                                        }
                                    } else {
                                        HStack(spacing: Theme.Spacing.small) {
                                            Image(systemName: "sparkles")
                                            Text("Generate Route")
                                                .fontWeight(.bold)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .primaryActionButton()
                                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isGenerating)
                                .opacity(viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
                            }
                        }
                        .standardCard()
                        .padding(.top, viewModel.generatedRoute == nil ? 0 : Theme.Spacing.medium)
                        
                        // --- 3. RESULT SECTION ---
                        if let route = viewModel.generatedRoute {
                            buildResultCard(route: route)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(Theme.Spacing.medium)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("AI Route Builder")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.generatedRoute != nil)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.isGenerating)
        }
    }
    
    @ViewBuilder
    private func buildResultCard(route: TrekRoute) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            
            // Header with Close Button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Text(route.summary)
                        .font(.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation { viewModel.clearRoute() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            
            // Embedded Map Preview
            Map(position: $viewModel.cameraPosition, interactionModes: []) {
                UserAnnotation()
                if let coords = route.routeCoordinates, coords.count > 1 {
                    let segments = RoutePolylineStyle.strokeSegments(for: route)
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        MapPolyline(coordinates: seg.coordinates)
                            .stroke(seg.color, style: RoutePolylineStyle.lineStyle)
                    }
                    
                    if let start = coords.first, let end = coords.last {
                        Marker("Start", systemImage: "figure.walk", coordinate: start.asCLLocationCoordinate)
                            .tint(Color(UIColor.systemGreen))
                        if start != end {
                            Marker("End", systemImage: "flag.checkered", coordinate: end.asCLLocationCoordinate)
                                .tint(Color(UIColor.systemRed))
                        }
                    }
                } else {
                    Marker(route.name, systemImage: "figure.walk", coordinate: route.startingCoordinate)
                        .tint(Color(UIColor.systemGreen))
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard, style: .continuous))
            
            // Metrics
            HStack(spacing: Theme.Spacing.large) {
                Label("\(String(format: "%.1f", route.distance)) km", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                if let time = route.estimatedDuration {
                    Label(time, systemImage: "clock")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                
                if let weather = route.weatherSummary {
                    Label(weather, systemImage: "cloud.sun")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }
            
            Divider()
            
            // Action Buttons
            if viewModel.hasSavedRoute {
                Button(action: {
                    withAnimation { viewModel.clearRoute() }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Saved to Library")
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.plain)
                .primaryActionButton(backgroundColor: Color(UIColor.systemGreen))
            } else {
                Button(action: {
                    CloudRouteManager.shared.saveRoute(route)
                    withAnimation { viewModel.hasSavedRoute = true }
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save to Cloud Library")
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.plain)
                .primaryActionButton(backgroundColor: Theme.Colors.secondary)
            }
        }
        .standardCard()
    }
}
