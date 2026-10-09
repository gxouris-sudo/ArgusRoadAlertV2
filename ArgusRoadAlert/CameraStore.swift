import Foundation
import CoreLocation

struct Camera: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: String   // speed_camera, maxspeed, ai, reported, police_report, police_station ...
    let lat: Double
    let lon: Double
    let source: String
    var time: Double? = nil
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var location: CLLocation { .init(latitude: lat, longitude: lon) }
}

private struct Overpass: Decodable {
    struct Center: Decodable { let lat: Double; let lon: Double }
    struct El: Decodable { let id: Int; let lat: Double?; let lon: Double?; let center: Center?; let tags: [String: String]? }
    let elements: [El]
}
private struct FeedItem: Decodable { let name: String; let kind: String?; let lat: Double; let lon: Double }

@MainActor
final class CameraStore: ObservableObject {
    @Published var cameras: [Camera] = []   // everything alerts can fire on (cameras + police reports)
    @Published var stations: [Camera] = []  // police stations (map only)
    @Published var status = "No data yet. Start monitoring."
    private var osm: [Camera] = []
    private var feed: [Camera] = []
    private var user: [Camera] = []
    private var sightings: [Camera] = []
    private var lastFetch: CLLocation?
    private var lastDate = Date.distantPast
    private var fetching = false
    private let d = UserDefaults.standard
    private let sightingTTL: Double = 7200

    init() {
        osm = load("osm"); user = load("user"); feed = load("feed")
        sightings = load("sight"); stations = load("stations")
        let cutoff = Date().timeIntervalSince1970 - sightingTTL
        sightings = sightings.filter { ($0.time ?? 0) > cutoff }
        merge()
    }
    private func load(_ k: String) -> [Camera] {
        guard let data = d.data(forKey: k) else { return [] }
        return (try? JSONDecoder().decode([Camera].self, from: data)) ?? []
    }
    private func save(_ k: String, _ v: [Camera]) { d.set(try? JSONEncoder().encode(v), forKey: k) }
    private func merge() {
        cameras = osm + feed + user + sightings
        if !cameras.isEmpty || !stations.isEmpty { status = "\(osm.count + feed.count + user.count) cameras, \(stations.count) stations, \(sightings.count) police reports" }
    }

    func prune() {
        let cutoff = Date().timeIntervalSince1970 - sightingTTL
        let before = sightings.count
        sightings = sightings.filter { ($0.time ?? 0) > cutoff }
        if sightings.count != before { save("sight", sightings); merge() }
    }

    func addReport(at l: CLLocation) {
        user.append(Camera(id: UUID().uuidString, name: "Reported camera", kind: "reported",
                           lat: l.coordinate.latitude, lon: l.coordinate.longitude, source: "You"))
        save("user", user); merge()
    }

    func addSighting(at l: CLLocation) {
        sightings.append(Camera(id: UUID().uuidString, name: "Police reported", kind: "police_report",
                                lat: l.coordinate.latitude, lon: l.coordinate.longitude, source: "You",
                                time: Date().timeIntervalSince1970))
        save("sight", sightings); merge()
    }

    func refreshIfNeeded(near loc: CLLocation) async {
        if let last = lastFetch, loc.distance(from: last) < 10_000, Date().timeIntervalSince(lastDate) < 1800 { return }
        guard !fetching else { return }
        fetching = true; defer { fetching = false }
        status = "Updating map data..."
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        let q = "[out:json][timeout:25];(node[\"highway\"=\"speed_camera\"](around:30000,\(lat),\(lon));node[\"enforcement\"~\"maxspeed|traffic_signals|average_speed\"](around:30000,\(lat),\(lon));nwr[\"amenity\"=\"police\"](around:30000,\(lat),\(lon)););out center body;"
        var req = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = ("data=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? q)).data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let r = try JSONDecoder().decode(Overpass.self, from: data)
            var cams: [Camera] = [], sts: [Camera] = []
            for e in r.elements {
                guard let la = e.lat ?? e.center?.lat, let lo = e.lon ?? e.center?.lon else { continue }
                let t = e.tags ?? [:]
                if t["amenity"] == "police" {
                    sts.append(Camera(id: "st\(e.id)", name: t["name"] ?? "Police station", kind: "police_station",
                                      lat: la, lon: lo, source: "OpenStreetMap"))
                } else {
                    let kind = t["enforcement"] ?? "speed_camera"
                    let name = t["name"] ?? (t["maxspeed"].map { "Camera (limit \($0))" } ?? "Enforcement camera")
                    cams.append(Camera(id: "osm\(e.id)", name: name, kind: kind, lat: la, lon: lo, source: "OpenStreetMap"))
                }
            }
            osm = cams; stations = sts
            save("osm", osm); save("stations", stations)
            lastFetch = loc; lastDate = Date()
        } catch { status = "Update failed, using cached data" }

        if let s = d.string(forKey: "feedURL"), let url = URL(string: s), !s.isEmpty {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let items = try? JSONDecoder().decode([FeedItem].self, from: data) {
                feed = items.enumerated().map { i, it in
                    Camera(id: "feed\(i)", name: it.name, kind: it.kind ?? "ai", lat: it.lat, lon: it.lon, source: "Custom feed")
                }
                save("feed", feed)
            }
        }
        merge()
    }
}
