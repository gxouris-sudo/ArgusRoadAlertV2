import SwiftUI
import CoreLocation

enum Theme {
    static let bg = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let card = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let line = Color(red: 0.23, green: 0.04, blue: 0.06)
    static let red = Color(red: 0.88, green: 0.11, blue: 0.18)
    static let hot = Color(red: 1, green: 0.23, blue: 0.29)
}

struct Card<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct RedButton: View {
    let title: String; var filled = true; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).tracking(1.5)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(filled ? .white : Theme.hot)
                .background(filled ? Theme.red.opacity(0.35) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.red))
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            RadarView().tabItem { Label("Radar", systemImage: "scope") }
            MapTabView().tabItem { Label("Map", systemImage: "map.fill") }
            CameraListView().tabItem { Label("Cameras", systemImage: "video.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(Theme.hot).preferredColorScheme(.dark)
    }
}

struct RadarView: View {
    @EnvironmentObject var loc: LocationService
    @EnvironmentObject var store: CameraStore
    @EnvironmentObject var alerts: AlertEngine
    @Environment(\.openURL) var openURL

    func fmt(_ d: Double) -> String { d >= 1000 ? String(format: "%.1f km", d / 1000) : "\(Int(d)) m" }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ARGUS ROAD ALERT").font(.system(size: 18, weight: .bold)).tracking(3).foregroundStyle(.white)
                    Text("GREECE  /  CAMERA WARNINGS").font(.system(size: 10)).tracking(3).foregroundStyle(.gray)
                    if let a = alerts.active {
                        Card {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.camera.kind == "police_report" ? "POLICE REPORTED AHEAD" : (a.urgent ? "CAMERA - SLOW DOWN" : "CAMERA AHEAD")).bold().foregroundStyle(Theme.hot)
                                Text(a.camera.name).foregroundStyle(.white)
                                Text("\(fmt(a.distance)) - \(a.camera.source)").font(.caption).foregroundStyle(.gray)
                            }
                        }.overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hot, lineWidth: 2))
                    }
                    Card {
                        VStack(alignment: .leading) {
                            Text(loc.running ? "MONITORING" : "STANDBY").font(.caption).foregroundStyle(loc.running ? .green : .gray)
                            Text(alerts.nearest.map { fmt($0.distance) } ?? "--")
                                .font(.system(size: 46, weight: .bold)).foregroundStyle(.white)
                            Text(alerts.nearest?.camera.name ?? "Nearest camera ahead").font(.caption).foregroundStyle(.gray)
                        }
                    }
                    Card { RadarMap() }
                    RedButton(title: loc.running ? "STOP" : "START MONITORING") {
                        if loc.running { loc.stop(); alerts.reset() } else { alerts.prepare(); loc.start() }
                    }
                    HStack {
                        RedButton(title: "REPORT HERE", filled: false) { if let l = loc.location { store.addReport(at: l) } }
                        RedButton(title: "OPEN WAZE", filled: false) { openURL(URL(string: "waze://")!) }
                    }
                    Text(store.status).font(.caption).foregroundStyle(.gray)
                }.padding()
            }
        }
    }
}

struct RadarMap: View {
    @EnvironmentObject var loc: LocationService
    @EnvironmentObject var store: CameraStore
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = min(size.width, size.height) / 2 - 8
            for f in [0.25, 0.5, 1.0] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * f, y: c.y - R * f, width: 2 * R * f, height: 2 * R * f)),
                           with: .color(Theme.line), lineWidth: 1)
            }
            guard let me = loc.location else { return }
            for cam in store.cameras {
                let d = me.distance(from: cam.location)
                if d > 2000 { continue }
                let dx = (cam.lon - me.coordinate.longitude) * 111_320 * cos(me.coordinate.latitude * .pi / 180)
                let dy = -(cam.lat - me.coordinate.latitude) * 110_540
                let p = CGPoint(x: c.x + dx / 2000 * R, y: c.y + dy / 2000 * R)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                         with: .color(d < 500 ? Theme.hot : Theme.red.opacity(0.6)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white))
        }.frame(height: 260)
    }
}

struct CameraListView: View {
    @EnvironmentObject var loc: LocationService
    @EnvironmentObject var store: CameraStore
    var sorted: [Camera] {
        guard let me = loc.location else { return store.cameras }
        return store.cameras.sorted { me.distance(from: $0.location) < me.distance(from: $1.location) }
    }
    var body: some View {
        NavigationStack {
            List(sorted.prefix(200)) { c in
                VStack(alignment: .leading) {
                    Text(c.name).foregroundStyle(.white)
                    Text("\(c.kind) - \(c.source)" + (loc.location.map { " - \(Int($0.distance(from: c.location))) m" } ?? ""))
                        .font(.caption).foregroundStyle(.gray)
                }.listRowBackground(Theme.card)
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Cameras")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var alerts: AlertEngine
    @AppStorage("warnDistance") var warn = 500.0
    @AppStorage("volume") var volume = 0.8
    @AppStorage("soundOn") var soundOn = true
    @AppStorage("voiceOn") var voiceOn = true
    @AppStorage("greek") var greek = true
    @AppStorage("feedURL") var feedURL = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Alert") {
                    VStack(alignment: .leading) { Text("Warn at \(Int(warn)) m"); Slider(value: $warn, in: 200...1500, step: 50) }
                    VStack(alignment: .leading) { Text("Volume"); Slider(value: $volume, in: 0...1) }
                    Toggle("Beep sound", isOn: $soundOn)
                    Toggle("Voice announcement", isOn: $voiceOn)
                    Toggle("Greek voice", isOn: $greek)
                    Button("Test alert sound") { alerts.play(3, speak: voiceOn ? (greek ? "Κάμερα σε 300 μέτρα" : "Camera ahead, 300 meters") : nil) }
                }
                Section("Custom camera feed (JSON URL)") {
                    TextField("https://.../cameras.json", text: $feedURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Format: [{\"name\":\"...\",\"kind\":\"ai\",\"lat\":37.97,\"lon\":23.72}]").font(.caption2).foregroundStyle(.gray)
                }
                Section { Text("Follow Greek traffic law. Do not handle the phone while driving.").font(.caption) }
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Settings")
        }
    }
}
