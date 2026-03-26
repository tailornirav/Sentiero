import Foundation
import CoreLocation
import SwiftUI
import MapKit
import Combine

@MainActor // Guarantees all UI state changes happen on the main thread
class AIGeneratedRouteViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // UI State variables
    @Published var prompt: String = ""
    @Published var isGenerating: Bool = false
    @Published var generatedRoute: TrekRoute? = nil
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var errorMessage: String? = nil
    @Published var hasSavedRoute: Bool = false
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // The bridge between the user's tap and your asynchronous AI pipeline
    func submitPrompt() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Lock the UI and show a loading state
        isGenerating = true
        errorMessage = nil
        generatedRoute = nil
        hasSavedRoute = false
        
        // Detach a new asynchronous task to prevent the app from freezing
        Task {
            do {
                // Grab the user's actual GPS coordinates to feed into your prompt
                let currentLocation = locationManager.location?.coordinate
                
                // Fire the pipeline
                let route = try await GeminiService.shared.generateRoute(from: prompt, userLocation: currentLocation)
                
                // Update UI state with animation
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    self.generatedRoute = route
                    
                    // Logically reposition the camera to the start of the new route
                    if let firstCoord = route.routeCoordinates?.first {
                        self.cameraPosition = .camera(MapCamera(
                            centerCoordinate: firstCoord.asCLLocationCoordinate,
                            distance: 4000, // 4km altitude provides a good overview of the trail
                            heading: 0,
                            pitch: 0
                        ))
                    }
                }
                
            } catch {
                self.errorMessage = "Failed to generate route. Please try again."
                print("Generation Error: \(error.localizedDescription)")
            }
            
            // Unlock the UI
            self.isGenerating = false
        }
    }
    
    func clearRoute() {
        withAnimation(.easeInOut) {
            generatedRoute = nil
            prompt = ""
            hasSavedRoute = false
            cameraPosition = .userLocation(fallback: .automatic)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Handle background location updates if necessary
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        if code != CLError.locationUnknown.rawValue {
            #if DEBUG
            print("AIGeneratedRouteViewModel location error: \(error.localizedDescription)")
            #endif
        }
    }
}
