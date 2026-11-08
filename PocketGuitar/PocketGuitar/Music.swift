import Foundation

let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
let openMidi = [40, 45, 50, 55, 59, 64]   // E2 A2 D3 G3 B3 E4

enum Quality: String, CaseIterable, Codable, Identifiable {
    case maj = "", min = "m", dom7 = "7", min7 = "m7", maj7 = "maj7", sus2 = "sus2", sus4 = "sus4"
    var id: String { rawValue }
    var label: String { self == .maj ? "Major" : (self == .min ? "Minor" : rawValue) }
}

struct Chord: Identifiable, Hashable, Codable {
    var id = UUID()
    var root: Int
    var quality: Quality
    var name: String { noteNames[root] + quality.rawValue }
    var frets: [Int] { Chord.shape(root, quality) }   // -1 = muted string

    static let open: [String: [Int]] = [
        "C": [-1,3,2,0,1,0], "D": [-1,-1,0,2,3,2], "G": [3,2,0,0,0,3], "Dm": [-1,-1,0,2,3,1],
        "C7": [-1,3,2,3,1,0], "D7": [-1,-1,0,2,1,2], "G7": [3,2,0,0,0,1], "Dm7": [-1,-1,0,2,1,1],
        "Cmaj7": [-1,3,2,0,0,0], "Dmaj7": [-1,-1,0,2,2,2], "Gmaj7": [3,2,0,0,0,2],
        "Dsus2": [-1,-1,0,2,3,0], "Dsus4": [-1,-1,0,2,3,3], "Gsus4": [3,3,0,0,1,3],
        "Gsus2": [3,0,0,0,3,3], "Csus4": [-1,3,3,0,1,1]]

    static func shape(_ r: Int, _ q: Quality) -> [Int] {
        if let o = open[noteNames[r] + q.rawValue] { return o }
        let e: [Quality: [Int]] = [.maj:[0,2,2,1,0,0], .min:[0,2,2,0,0,0], .dom7:[0,2,0,1,0,0],
                                   .min7:[0,2,0,0,0,0], .maj7:[0,2,1,1,0,0], .sus4:[0,2,2,2,0,0]]
        let a: [Quality: [Int]] = [.maj:[-1,0,2,2,2,0], .min:[-1,0,2,2,1,0], .dom7:[-1,0,2,0,2,0],
                                   .min7:[-1,0,2,0,1,0], .maj7:[-1,0,2,1,2,0], .sus2:[-1,0,2,2,0,0],
                                   .sus4:[-1,0,2,2,3,0]]
        let ef = (r + 8) % 12, af = (r + 3) % 12
        if let t = e[q], ef <= af || a[q] == nil { return t.map { $0 < 0 ? $0 : $0 + ef } }
        return (a[q] ?? [-1,0,2,2,2,0]).map { $0 < 0 ? $0 : $0 + af }
    }
}

// 16 sixteenth-note steps. D/d down (strong/soft), U/u up, x = muted chop, 1-6 = pluck string (1 = lowest)
struct Rhythm: Identifiable { let id: String; let pattern: String }
let rhythms = [
    Rhythm(id: "Folk / Campfire", pattern: "D...D.U...U.D.U."),
    Rhythm(id: "Rock",            pattern: "D.D.D.D.D.D.D.Du"),
    Rhythm(id: "Pop",             pattern: "D...D.U.U.U.D.U."),
    Rhythm(id: "Country",         pattern: "1...D.u.3...D.u."),
    Rhythm(id: "Fingerstyle",     pattern: "1.3.4.5.4.3.2.3."),
    Rhythm(id: "Reggae",          pattern: "..u...u...u...u."),
    Rhythm(id: "Ballad",          pattern: "D.......D.u.D.U."),
    Rhythm(id: "Flamenco",        pattern: "DuDuD.D.DuDuD.D."),
]

func ch(_ s: String) -> Chord {
    let n = s.count > 1 && s[s.index(after: s.startIndex)] == "#" ? 2 : 1
    return Chord(root: noteNames.firstIndex(of: String(s.prefix(n))) ?? 0,
                 quality: Quality(rawValue: String(s.dropFirst(n))) ?? .maj)
}

struct Preset: Identifiable {
    let id = UUID()
    let name: String, chords: [Chord], rhythm: String, bpm: Double, capo: Int
    init(_ n: String, _ c: [String], _ r: String, _ b: Double, _ capo: Int = 0) {
        name = n; chords = c.map(ch); rhythm = r; bpm = b; self.capo = capo
    }
    static let all = [
        Preset("Campfire Classic", ["G","C","D","G"], "Folk / Campfire", 96),
        Preset("Pop Four", ["C","G","Am","F"], "Pop", 100),
        Preset("Rock Drive", ["E","A","B","A"], "Rock", 132),
        Preset("Country Strut", ["G","Em","C","D"], "Country", 112),
        Preset("Reggae Skank", ["C","F","G","F"], "Reggae", 76),
        Preset("Slow Ballad", ["D","Bm","G","A"], "Ballad", 70, 2),
        Preset("Fingerstyle Etude", ["Am","C","G","Em"], "Fingerstyle", 84),
        Preset("Flamenco Descent", ["Am","G","F","E"], "Flamenco", 120),
    ]
}
