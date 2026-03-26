import MapKit
import SwiftUI
import UIKit

/// MKMapView with draggable waypoint pins and a polyline overlay. Updates `waypoints` when a drag ends.
struct CustomEditMapView: UIViewRepresentable {
    @Binding var waypoints: [CLLocationCoordinate2D]
    var displayPolyline: [CLLocationCoordinate2D]
    /// When this changes (e.g. entering edit mode), the map fits bounds once.
    var mapFitToken: Int
    var onWaypointCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(waypoints: $waypoints, onWaypointCommit: onWaypointCommit)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        context.coordinator.mapView = map
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onWaypointCommit = onWaypointCommit
        context.coordinator.waypointsBinding = $waypoints

        if context.coordinator.lastMapFitToken != mapFitToken {
            context.coordinator.lastMapFitToken = mapFitToken
            context.coordinator.waypointFitDone = false
            context.coordinator.polylineFitDone = false
        }

        if context.coordinator.isDragging {
            context.coordinator.refreshPolylineOnly(mapView: mapView, polyline: displayPolyline)
            return
        }

        context.coordinator.rebuildAnnotations(mapView: mapView, waypoints: waypoints)
        context.coordinator.refreshPolylineOnly(mapView: mapView, polyline: displayPolyline)

        if !displayPolyline.isEmpty, !context.coordinator.polylineFitDone {
            context.coordinator.fitMap(mapView: mapView, waypoints: waypoints, polyline: displayPolyline)
            context.coordinator.polylineFitDone = true
        } else if displayPolyline.isEmpty, waypoints.count >= 2, !context.coordinator.waypointFitDone {
            context.coordinator.fitMap(mapView: mapView, waypoints: waypoints, polyline: [])
            context.coordinator.waypointFitDone = true
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var waypointsBinding: Binding<[CLLocationCoordinate2D]>
        var onWaypointCommit: () -> Void
        weak var mapView: MKMapView?
        var isDragging = false
        var lastMapFitToken: Int = -1
        var waypointFitDone = false
        var polylineFitDone = false
        private var dragStartCoordinate: CLLocationCoordinate2D?

        init(waypoints: Binding<[CLLocationCoordinate2D]>, onWaypointCommit: @escaping () -> Void) {
            self.waypointsBinding = waypoints
            self.onWaypointCommit = onWaypointCommit
        }

        func rebuildAnnotations(mapView: MKMapView, waypoints: [CLLocationCoordinate2D]) {
            let sorted = mapView.annotations.compactMap { $0 as? WaypointAnnotation }.sorted { $0.waypointIndex < $1.waypointIndex }
            if sorted.count == waypoints.count,
               zip(sorted, waypoints).allSatisfy({ abs($0.coordinate.latitude - $1.latitude) < 1e-8 && abs($0.coordinate.longitude - $1.longitude) < 1e-8 }) {
                return
            }

            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            for (index, coord) in waypoints.enumerated() {
                let ann = WaypointAnnotation()
                ann.waypointIndex = index
                ann.coordinate = coord
                ann.title = "Waypoint \(index + 1)"
                mapView.addAnnotation(ann)
            }
        }

        func refreshPolylineOnly(mapView: MKMapView, polyline: [CLLocationCoordinate2D]) {
            mapView.removeOverlays(mapView.overlays)
            guard polyline.count >= 2 else { return }
            let mk = MKPolyline(coordinates: polyline, count: polyline.count)
            mapView.addOverlay(mk)
        }

        func fitMap(mapView: MKMapView, waypoints: [CLLocationCoordinate2D], polyline: [CLLocationCoordinate2D]) {
            var coords = polyline.isEmpty ? waypoints : polyline
            if coords.isEmpty { return }
            var rect = MKMapRect.null
            for c in coords {
                let p = MKMapPoint(c)
                rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
            }
            let pad = UIEdgeInsets(top: 50, left: 40, bottom: 50, right: 40)
            mapView.setVisibleMapRect(rect, edgePadding: pad, animated: false)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "waypoint.marker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = false
            view.isDraggable = true
            if let wa = annotation as? WaypointAnnotation {
                view.glyphText = "\(wa.waypointIndex + 1)"
            }
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting:
                isDragging = true
                dragStartCoordinate = view.annotation?.coordinate
            case .dragging:
                break
            case .ending:
                isDragging = false
                defer { view.setDragState(.none, animated: true) }
                guard let ann = view.annotation as? WaypointAnnotation else { return }
                let idx = ann.waypointIndex
                let coord = view.annotation?.coordinate ?? ann.coordinate
                guard waypointsBinding.wrappedValue.indices.contains(idx) else { return }
                var w = waypointsBinding.wrappedValue
                w[idx] = coord
                waypointsBinding.wrappedValue = w
                ann.coordinate = coord
                onWaypointCommit()
            case .canceling:
                isDragging = false
                defer { view.setDragState(.none, animated: true) }
                if let start = dragStartCoordinate,
                   let pointAnn = view.annotation as? MKPointAnnotation {
                    pointAnn.coordinate = start
                }
            @unknown default:
                isDragging = false
                view.setDragState(.none, animated: true)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor.systemBlue
                r.lineWidth = 5
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

final class WaypointAnnotation: MKPointAnnotation {
    var waypointIndex: Int = 0
}
