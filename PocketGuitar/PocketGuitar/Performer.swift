import SwiftUI

let amber = Color(red: 1.0, green: 0.70, blue: 0.20)

final class Performer: ObservableObject {
    let audio = GuitarEngine()
    @Published var chords: [Chord] = []
    @Published var rhythm = rhythms[0]
    @Published var bpm: Double = 96 { didSet { if timer != nil { schedule() } } }
    @Published var capo = 0
    @Published var active: Int?
    @Published var step = 0
    @Published var playing = false
    @Published var palm = false
    private var timer: DispatchSourceTimer?
    private var chordIdx = 0, stepIdx = 0
    private var taps: [Date] = []

    init() { apply(Preset.all[0]) }

    func apply(_ p: Preset) {
        stopLoop()
        chords = p.chords; bpm = p.bpm; capo = p.capo
        rhythm = rhythms.first { $0.id == p.rhythm } ?? rhythms[0]
    }

    func lifecycle(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on   // keep screen awake while app is in use
        if on { audio.start() } else { stopLoop(); audio.pause() }
    }

    func startLoop(_ i: Int) {
        stopLoop()
        guard i < chords.count else { return }
        chordIdx = i; stepIdx = 0; active = i; playing = true
        fire(); schedule()
    }

    func stopLoop() {
        timer?.cancel(); timer = nil
        playing = false; active = nil
    }

    func strumOnce(_ i: Int, down: Bool) {
        guard i < chords.count else { return }
        audio.strum(chords[i].frets, capo: capo, down: down, vel: down ? 0.95 : 0.8)
    }

    func preview(_ c: Chord) { audio.strum(c.frets, capo: capo, down: true, vel: 0.95) }

    func setPalm(_ on: Bool) {
        palm = on; audio.palmMuted = on
        if on { audio.muteAll(ms: 15) }
    }

    func tapTempo() {
        let now = Date()
        if let l = taps.last, now.timeIntervalSince(l) > 2 { taps = [] }
        taps = Array((taps + [now]).suffix(5))
        if taps.count >= 2, let f = taps.first, let l = taps.last {
            let iv = l.timeIntervalSince(f) / Double(taps.count - 1)
            bpm = min(240, max(60, (60 / iv).rounded()))
        }
    }

    private func schedule() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        let iv = 60.0 / bpm / 4
        t.schedule(deadline: .now() + iv, repeating: iv, leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.fire() }
        t.resume(); timer = t
    }

    private func fire() {
        guard chordIdx < chords.count else { stopLoop(); return }
        let pat = Array(rhythm.pattern)
        step = stepIdx
        play(pat[stepIdx % pat.count], chords[chordIdx].frets)
        stepIdx = (stepIdx + 1) % pat.count
    }

    private func play(_ c: Character, _ f: [Int]) {
        switch c {
        case "D": audio.strum(f, capo: capo, down: true, vel: 1.0)
        case "d": audio.strum(f, capo: capo, down: true, vel: 0.62)
        case "U": audio.strum(f, capo: capo, down: false, vel: 0.8)
        case "u": audio.strum(f, capo: capo, down: false, vel: 0.5)
        case "x": audio.strum(f, capo: capo, down: true, vel: 0.55, chop: true)
        default:
            if let d = c.wholeNumberValue, (1...6).contains(d) {
                let played = (0..<6).filter { f[$0] >= 0 }
                let s = played.first { $0 >= d - 1 } ?? played.last ?? 0
                audio.pluck(string: s, fret: f[s], capo: capo, vel: 0.85, delayMs: Double.random(in: 0...4))
            }
        }
    }
}
