import Foundation
import CoreLocation
import AVFoundation
import UIKit
import UserNotifications

struct ActiveAlert { let camera: Camera; let distance: Double; let time: Date; let urgent: Bool }
struct Nearest { let camera: Camera; let distance: Double }

@MainActor
final class AlertEngine: NSObject, ObservableObject {
    @Published var active: ActiveAlert?
    @Published var nearest: Nearest?
    private var warned = Set<String>()
    private var urgent = Set<String>()
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private let d = UserDefaults.standard

    private var warnDistance: Double { d.object(forKey: "warnDistance") as? Double ?? 500 }
    private var volume: Double { d.object(forKey: "volume") as? Double ?? 0.8 }
    private var soundOn: Bool { d.object(forKey: "soundOn") as? Bool ?? true }
    private var voiceOn: Bool { d.object(forKey: "voiceOn") as? Bool ?? true }
    private var greek: Bool { d.object(forKey: "greek") as? Bool ?? true }

    func prepare() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    func reset() { warned.removeAll(); urgent.removeAll(); active = nil; nearest = nil }

    func evaluate(_ loc: CLLocation, cameras: [Camera]) {
        let warnAt = max(warnDistance, max(loc.speed, 0) * 15)
        var best: Nearest?
        for c in cameras {
            let dist = loc.distance(from: c.location)
            if dist > warnAt * 1.5 { warned.remove(c.id); urgent.remove(c.id) }
            if dist > 4000 || !isAhead(loc, c) { continue }
            if best == nil || dist < best!.distance { best = Nearest(camera: c, distance: dist) }
            if dist < 150, !urgent.contains(c.id) {
                urgent.insert(c.id); warned.insert(c.id); fire(c, dist, urgent: true)
            } else if dist < warnAt, !warned.contains(c.id) {
                warned.insert(c.id); fire(c, dist, urgent: false)
            }
        }
        nearest = best
        if let a = active, Date().timeIntervalSince(a.time) > 8 { active = nil }
    }

    private func isAhead(_ l: CLLocation, _ c: Camera) -> Bool {
        guard l.speed > 2, l.course >= 0 else { return true }
        let p1 = l.coordinate.latitude * .pi / 180, p2 = c.lat * .pi / 180
        let dl = (c.lon - l.coordinate.longitude) * .pi / 180
        let y = sin(dl) * cos(p2), x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let b = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        var diff = abs(b - l.course).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        return diff < 70
    }

    private func fire(_ c: Camera, _ dist: Double, urgent u: Bool) {
        active = ActiveAlert(camera: c, distance: dist, time: Date(), urgent: u)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let m = Int((dist / 10).rounded() * 10)
        let police = c.kind == "police_report"
        let text = police ? (greek ? "Αστυνομία σε \(m) μέτρα" : "Police reported ahead, \(m) meters")
                          : (greek ? "Κάμερα σε \(m) μέτρα" : "Camera ahead, \(m) meters")
        play(u ? 6 : 3, speak: voiceOn ? text : nil)
        if UIApplication.shared.applicationState != .active {
            let n = UNMutableNotificationContent()
            n.title = police ? "Police reported ahead" : "Camera ahead"; n.body = "\(c.name) - \(m) m"; n.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
        }
    }

    func play(_ n: Int, speak: String? = nil) {
        guard soundOn else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? s.setActive(true)
        player = try? AVAudioPlayer(data: Self.wav(n))
        player?.volume = Float(volume)
        player?.play()
        let dur = player?.duration ?? 1
        if let t = speak {
            DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.1) { [weak self] in
                guard let self else { return }
                let u = AVSpeechUtterance(string: t)
                u.voice = AVSpeechSynthesisVoice(language: self.greek ? "el-GR" : "en-US")
                u.volume = Float(self.volume)
                self.synth.speak(u)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64((dur + (speak != nil ? 3.5 : 0.4)) * 1e9))
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func wav(_ beeps: Int) -> Data {
        let sr = 44100
        var pcm = [Int16]()
        for _ in 0..<beeps {
            for i in 0..<(sr * 16 / 100) {
                pcm.append(Int16(sin(2 * Double.pi * 1100 * Double(i) / Double(sr)) * 0.8 * 32767))
            }
            pcm += [Int16](repeating: 0, count: sr * 12 / 100)
        }
        var d = Data()
        func s(_ x: String) { d.append(x.data(using: .ascii)!) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        s("RIFF"); u32(UInt32(36 + pcm.count * 2)); s("WAVE"); s("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16); s("data"); u32(UInt32(pcm.count * 2))
        pcm.forEach { u16(UInt16(bitPattern: $0)) }
        return d
    }
}
