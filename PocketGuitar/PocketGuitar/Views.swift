import SwiftUI

struct ChordDiagram: View {
    let frets: [Int]
    var body: some View {
        Canvas { ctx, size in
            let played = frets.filter { $0 > 0 }
            let base = (played.max() ?? 0) > 4 ? (played.min() ?? 1) : 1
            let top: CGFloat = 16, h = size.height - top
            let left = size.width * 0.14, right = size.width * 0.86
            let sp = (right - left) / 5, fh = h / 5
            func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ o: Double) {
                ctx.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(.white.opacity(o)), lineWidth: w)
            }
            for s in 0..<6 { let x = left + sp * CGFloat(s); line(CGPoint(x: x, y: top), CGPoint(x: x, y: size.height), 1 + CGFloat(5 - s) * 0.25, 0.7) }
            for f in 0...5 { let y = top + fh * CGFloat(f); line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), f == 0 && base == 1 ? 4 : 1, 0.6) }
            if base > 1 { ctx.draw(Text("\(base)fr").font(.system(size: 10)).foregroundColor(.gray), at: CGPoint(x: right + 2, y: top + fh / 2), anchor: .leading) }
            for s in 0..<6 {
                let f = frets[s], x = left + sp * CGFloat(s)
                if f < 0 { ctx.draw(Text("×").font(.system(size: 13, weight: .bold)).foregroundColor(.gray), at: CGPoint(x: x, y: 7)) }
                else if f == 0 { ctx.stroke(Path(ellipseIn: CGRect(x: x - 4, y: 3, width: 8, height: 8)), with: .color(.white.opacity(0.8)), lineWidth: 1.5) }
                else {
                    let r = min(sp, fh) * 0.38, y = top + fh * (CGFloat(f - base) + 0.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(amber))
                }
            }
        }
        .aspectRatio(1.15, contentMode: .fit)
    }
}

struct PadView: View {
    @EnvironmentObject var p: Performer
    let chord: Chord, index: Int
    @State private var work: DispatchWorkItem?
    @State private var mode = 0          // 0 pending/tap, 1 holding, 2 swiped
    @State private var touching = false

    var body: some View {
        let on = p.active == index
        VStack(spacing: 6) {
            Text(chord.name).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(on ? amber : .white)
            ChordDiagram(frets: chord.frets).padding(.horizontal, 8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(on ? amber.opacity(0.25) : Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(on ? amber : .white.opacity(0.1), lineWidth: 3))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !touching {
                    touching = true; mode = 0
                    let w = DispatchWorkItem { if mode == 0 { mode = 1; p.startLoop(index) } }
                    work = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: w)
                }
                if mode != 2, abs(g.translation.height) > 28 {
                    work?.cancel()
                    if mode == 1 { p.stopLoop() }
                    mode = 2
                    p.strumOnce(index, down: g.translation.height > 0)
                }
            }
            .onEnded { _ in
                work?.cancel()
                if mode == 1 { p.stopLoop() } else if mode == 0 { p.strumOnce(index, down: true) }
                touching = false; mode = 0
            })
    }
}

struct PalmMuteButton: View {
    @EnvironmentObject var p: Performer
    var body: some View {
        Text("PALM MUTE").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.red.opacity(p.palm ? 1 : 0.8)))
            .scaleEffect(p.palm ? 0.97 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !p.palm { p.setPalm(true) } }
                .onEnded { _ in p.setPalm(false) })
    }
}

struct PlayView: View {
    @EnvironmentObject var p: Performer

    var steps: some View {
        let pat = Array(p.rhythm.pattern)
        return HStack(spacing: 4) {
            ForEach(0..<pat.count, id: \.self) { i in
                Capsule().fill(p.playing && p.step == i ? amber : .white.opacity(pat[i] == "." ? 0.1 : 0.35))
                    .frame(height: pat[i] == "." ? 8 : 18)
            }
        }.frame(height: 20)
    }

    var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text(p.rhythm.id).bold()
                Spacer()
                Text("\(Int(p.bpm)) BPM" + (p.capo > 0 ? " · Capo \(p.capo)" : ""))
            }.foregroundColor(amber).font(.subheadline)
            steps
        }
    }

    func pads(cols: Int) -> some View {
        let n = p.chords.count
        let rows = stride(from: 0, to: n, by: cols).map { Array($0..<min($0 + cols, n)) }
        return VStack(spacing: 12) {
            ForEach(rows, id: \.first) { r in
                HStack(spacing: 12) {
                    ForEach(r, id: \.self) { i in PadView(chord: p.chords[i], index: i) }
                    ForEach(0..<(cols - r.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let cols = max(1, min(p.chords.count, wide ? 4 : 2))
            ZStack {
                Color.black.ignoresSafeArea()
                if p.chords.isEmpty {
                    Text("Add chords in Setup").foregroundColor(.gray)
                } else if wide {
                    HStack(spacing: 12) {
                        pads(cols: cols)
                        VStack(spacing: 12) { header; PalmMuteButton() }.frame(width: min(260, geo.size.width * 0.3))
                    }.padding()
                } else {
                    VStack(spacing: 12) { header; pads(cols: cols); PalmMuteButton().frame(height: 90) }.padding()
                }
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var p: Performer
    @State private var root = 7
    @State private var quality = Quality.maj
    var built: Chord { Chord(root: root, quality: quality) }

    var body: some View {
        NavigationStack {
            List {
                Section("Song presets") {
                    ForEach(Preset.all) { pr in
                        Button { p.apply(pr) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pr.name).foregroundColor(.white)
                                Text(pr.chords.map(\.name).joined(separator: " – ") + " · \(pr.rhythm) · \(Int(pr.bpm)) BPM" + (pr.capo > 0 ? " · Capo \(pr.capo)" : ""))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Section("Progression (tap ▶ to preview, Edit to reorder)") {
                    ForEach(p.chords) { c in
                        HStack {
                            Text(c.name).font(.title3.bold())
                            Spacer()
                            ChordDiagram(frets: c.frets).frame(width: 64, height: 56)
                            Button { p.preview(c) } label: { Image(systemName: "play.circle.fill").font(.title2) }.buttonStyle(.borderless)
                        }
                    }
                    .onMove { p.chords.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { p.chords.remove(atOffsets: $0) }
                }
                Section("Chord builder") {
                    HStack {
                        Picker("Root", selection: $root) { ForEach(0..<12, id: \.self) { Text(noteNames[$0]).tag($0) } }
                        Picker("Quality", selection: $quality) { ForEach(Quality.allCases) { Text($0.label).tag($0) } }
                    }.pickerStyle(.menu)
                    HStack {
                        Text(built.name).font(.title2.bold())
                        ChordDiagram(frets: built.frets).frame(height: 80)
                    }
                    HStack {
                        Button("Preview") { p.preview(built) }.buttonStyle(.borderless)
                        Spacer()
                        Button("Add to progression") { if p.chords.count < 8 { p.chords.append(built) } }
                            .buttonStyle(.borderless).disabled(p.chords.count >= 8)
                    }
                }
                Section("Rhythm") {
                    ForEach(rhythms) { r in
                        Button { p.rhythm = r } label: {
                            HStack { Text(r.id).foregroundColor(.white); Spacer()
                                if p.rhythm.id == r.id { Image(systemName: "checkmark").foregroundColor(amber) } }
                        }
                    }
                }
                Section("Tempo") {
                    Text("\(Int(p.bpm)) BPM").font(.headline)
                    Slider(value: $p.bpm, in: 60...240, step: 1)
                    Button("Tap tempo") { p.tapTempo() }.buttonStyle(.borderless)
                }
                Section("Capo") {
                    Stepper("Capo: \(p.capo)", value: $p.capo, in: 0...7)
                    Text("Shapes stay the same; sound rises \(p.capo) semitone\(p.capo == 1 ? "" : "s").")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Setup")
            .toolbar { EditButton() }
        }
    }
}

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Label("Hold a chord pad to repeat the rhythm; lift to stop.", systemImage: "hand.tap")
                Label("Tap a pad quickly for a single strum.", systemImage: "hand.point.up")
                Label("Swipe down for a bass-to-treble downstrum, up for treble-to-bass.", systemImage: "arrow.up.arrow.down")
                Label("Hold Palm Mute (red) with another finger to stop ringing notes and play muted.", systemImage: "hand.raised.fill")
                Label("Setup: pick a preset, build your own progression, choose rhythm, tempo (60–240) and capo (0–7).", systemImage: "slider.horizontal.3")
                Label("Everything is synthesized on-device, so it works fully offline.", systemImage: "airplane")
            }
            .navigationTitle("How to Play")
        }
    }
}
