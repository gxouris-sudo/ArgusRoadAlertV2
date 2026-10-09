import SwiftUI
import MapKit

final class PinAnnotation: NSObject, MKAnnotation {
    let item: Camera
    var coordinate: CLLocationCoordinate2D { item.coordinate }
    var title: String? { item.name }
    var subtitle: String? {
        if item.kind == "police_report", let t = item.time {
            return "\(max(0, Int((Date().timeIntervalSince1970 - t) / 60))) min ago - \(item.source)"
        }
        return item.kind == "police_station" ? "Police station" : "\(item.kind) - \(item.source)"
    }
    init(_ c: Camera) { item = c }
}

struct ArgusMap: UIViewRepresentable {
    var items: [Camera]
    var location: CLLocation?
    var recenter: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.mapType = .mutedStandard
        m.pointOfInterestFilter = .excludingAll
        m.showsUserLocation = true
        m.showsCompass = true
        m.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        m.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.3, longitude: 23.8),
                                       span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)), animated: false)
        // Red tint layer so the whole map follows the app theme
        var corners = [CLLocationCoordinate2D(latitude: -80, longitude: -179), CLLocationCoordinate2D(latitude: 80, longitude: -179),
                       CLLocationCoordinate2D(latitude: 80, longitude: 179), CLLocationCoordinate2D(latitude: -80, longitude: 179)]
        m.addOverlay(MKPolygon(coordinates: &corners, count: 4), level: .aboveRoads)
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        let c = context.coordinator
        let wanted = Set(items.map { $0.id })
        let existing = m.annotations.compactMap { $0 as? PinAnnotation }
        let have = Set(existing.map { $0.item.id })
        m.removeAnnotations(existing.filter { !wanted.contains($0.item.id) })
        m.addAnnotations(items.filter { !have.contains($0.id) }.map { PinAnnotation($0) })
        if let l = location, !c.centered {
            c.centered = true
            m.setRegion(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 8000, longitudinalMeters: 8000), animated: true)
        }
        if recenter != c.lastRecenter {
            c.lastRecenter = recenter
            m.setUserTrackingMode(.follow, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var centered = false
        var lastRecenter = 0

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolygonRenderer(polygon: poly)
            r.fillColor = UIColor(red: 0.88, green: 0.11, blue: 0.18, alpha: 0.14)
            r.strokeColor = .clear
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let p = annotation as? PinAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation) as! MKMarkerAnnotationView
            switch p.item.kind {
            case "police_station":
                v.markerTintColor = UIColor(red: 0.25, green: 0.45, blue: 1, alpha: 1)
                v.glyphImage = UIImage(systemName: "shield.fill"); v.clusteringIdentifier = "station"
            case "police_report":
                v.markerTintColor = UIColor(red: 1, green: 0.62, blue: 0.1, alpha: 1)
                v.glyphImage = UIImage(systemName: "car.fill"); v.clusteringIdentifier = "police"
            default:
                v.markerTintColor = UIColor(red: 0.88, green: 0.11, blue: 0.18, alpha: 1)
                v.glyphImage = UIImage(systemName: "video.fill"); v.clusteringIdentifier = "cam"
            }
            v.canShowCallout = true
            return v
        }
    }
}

struct MapChip: View {
    let title: String; let on: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(1)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(on ? .white : .gray)
                .background(on ? Theme.red.opacity(0.55) : Theme.card.opacity(0.9))
                .overlay(Capsule().stroke(on ? Theme.hot : Theme.line))
                .clipShape(Capsule())
        }
    }
}

struct MapTabView: View {
    @EnvironmentObject var loc: LocationService
    @EnvironmentObject var store: CameraStore
    @State private var showCams = true
    @State private var showStations = true
    @State private var showPolice = true
    @State private var recenter = 0

    var items: [Camera] {
        var r: [Camera] = []
        if showCams { r += store.cameras.filter { $0.kind != "police_report" } }
        if showPolice { r += store.cameras.filter { $0.kind == "police_report" } }
        if showStations { r += store.stations }
        return r
    }

    var body: some View {
        ArgusMap(items: items, location: loc.location, recenter: recenter)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    MapChip(title: "CAMERAS", on: showCams) { showCams.toggle() }
                    MapChip(title: "STATIONS", on: showStations) { showStations.toggle() }
                    MapChip(title: "POLICE", on: showPolice) { showPolice.toggle() }
                }.padding(.top, 8)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    HStack {
                        Text(store.status).font(.caption2).foregroundStyle(.gray)
                            .padding(8).background(Theme.card.opacity(0.9)).clipShape(Capsule())
                        Spacer()
                        Button { recenter += 1 } label: {
                            Image(systemName: "location.fill").foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(Theme.red.opacity(0.7)).clipShape(Circle())
                        }
                    }
                    RedButton(title: "REPORT POLICE HERE") { if let l = loc.location { store.addSighting(at: l) } }
                        .background(Theme.bg.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding()
            }
            .onAppear { if loc.location == nil { loc.start() } }
    }
}
