import AVFoundation
import os

/// One Karplus-Strong string with a fractional-delay allpass for accurate tuning.
final class Voice {
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: 2048)
    var len = 1, pos = 0, delay = 0
    var prev: Float = 0, apx: Float = 0, apy: Float = 0, c: Float = 0
    var decay: Float = 0.999, gain: Float = 0, fade: Float = 0, rel: Float = 1
    var active = false
    init() { buf.initialize(repeating: 0, count: 2048) }
}

final class GuitarEngine {
    private let engine = AVAudioEngine()
    private var src: AVAudioSourceNode?
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private let voices = (0..<12).map { _ in Voice() }   // two voices per string (clean re-pluck)
    private var toggle = [Int](repeating: 0, count: 6)
    private var sr: Double = 44100
    var palmMuted = false

    init() {
        lock.initialize(to: os_unfair_lock())
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: t) else { return }
            if type == .began { self?.muteAll(ms: 10) } else { self?.start() }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.start() }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let s = self else { return }
            if let n = s.src { s.engine.detach(n) }
            s.src = nil; s.start()
        }
    }

    func start() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setPreferredIOBufferDuration(0.005)
        try? s.setActive(true)
        if src == nil {
            let r = engine.outputNode.outputFormat(forBus: 0).sampleRate
            sr = r > 0 ? r : 44100
            let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
            let node = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl in
                let list = UnsafeMutableAudioBufferListPointer(abl)
                if let p = list[0].mData?.assumingMemoryBound(to: Float.self) { self.render(p, Int(frames)) }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: fmt)
            src = node
        }
        if !engine.isRunning { try? engine.start() }
    }

    func pause() { muteAll(ms: 20); engine.pause() }

    private func render(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        for i in 0..<n { out[i] = 0 }
        for v in voices where v.active {
            for i in 0..<n {
                if v.delay > 0 { v.delay -= 1; continue }
                let o = v.buf[v.pos]
                let lp = 0.5 * (o + v.prev) * v.decay
                let y = v.c * lp + v.apx - v.c * v.apy
                v.apx = lp; v.apy = y; v.prev = o
                v.buf[v.pos] = y
                v.pos += 1; if v.pos >= v.len { v.pos = 0 }
                out[i] += o * v.gain * v.fade
                v.fade *= v.rel
                if v.fade < 0.0003 { v.active = false; break }
            }
        }
        for i in 0..<n { out[i] = tanhf(out[i] * 0.7) }
    }

    func pluck(string s: Int, fret: Int, capo: Int, vel: Float, delayMs: Double, t60: Double? = nil) {
        let f = 440 * pow(2.0, Double(openMidi[s] + fret + capo - 69) / 12)
        let n = sr / f - 0.5
        let L = min(2040, Int(n)), frac = n - Double(L)
        let c = Float((1 - frac) / (1 + frac))
        let T60 = t60 ?? (palmMuted ? 0.22 : 2.8)
        let d = Float(pow(10.0, -3.0 / (f * T60)))
        let bright = 0.3 + 0.5 * vel
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        voices[s * 2 + toggle[s]].rel = Float(pow(0.001, 1.0 / (0.012 * sr)))   // fade the previous note fast
        toggle[s] ^= 1
        let v = voices[s * 2 + toggle[s]]
        var lpv: Float = 0, sum: Float = 0
        for i in 0..<L { lpv += bright * (Float.random(in: -1...1) - lpv); v.buf[i] = lpv; sum += lpv }
        let mean = sum / Float(L)
        for i in 0..<L { v.buf[i] = (v.buf[i] - mean) * 1.6 }
        v.len = L; v.pos = 0; v.prev = 0; v.apx = 0; v.apy = 0; v.c = c; v.decay = d
        v.gain = vel * 0.45; v.fade = 1; v.rel = 1
        v.delay = Int(delayMs / 1000 * sr); v.active = true
    }

    func strum(_ frets: [Int], capo: Int, down: Bool, vel: Float, chop: Bool = false) {
        var idx = (0..<6).filter { frets[$0] >= 0 }
        if !down { idx = Array(idx.suffix(4).reversed()) }          // upstrokes favour treble strings
        let spread = chop ? 5.0 : (vel > 0.8 ? 9.0 : 13.0)
        let jitter = Double.random(in: 0...6)
        for (k, s) in idx.enumerated() {
            let shape: Float = down ? 1 - 0.05 * Float(k) : 0.8 + 0.05 * Float(k)
            pluck(string: s, fret: frets[s], capo: capo, vel: vel * shape * Float.random(in: 0.88...1),
                  delayMs: jitter + Double(k) * spread * Double.random(in: 0.85...1.15), t60: chop ? 0.09 : nil)
        }
    }

    func muteAll(ms: Double = 15) {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        for v in voices {
            if v.delay > 0 { v.active = false }
            v.rel = Float(pow(0.001, 1.0 / (ms / 1000 * sr)))
        }
    }
}
