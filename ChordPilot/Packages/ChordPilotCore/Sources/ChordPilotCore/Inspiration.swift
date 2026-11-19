import Foundation

/// A note of a recorded track, in 16th-note steps.
public struct RecordedNote: Equatable {
    public var step: Int, note: Int, velocity: Int, length: Int
    public init(step: Int, note: Int, velocity: Int, length: Int) {
        self.step = step; self.note = note; self.velocity = velocity; self.length = length
    }
}

public struct InspirationOption {
    public var name: String
    public var events: [PatternEvent]
}

public struct InspirationResult {
    public var key: Key
    public var chords: [Chord]
    public var options: [InspirationOption]
}

/// Inspiration: analyses a recorded track (key, chord of each bar, rhythm, top line) and proposes
/// 10 melodies that follow it. Same algorithm as the web and desktop engines.
public enum Inspiration {
    public static let names = ["Contrappunto", "Contrappunto II", "Armonia in terza", "Armonia in sesta", "Risposta",
                               "Eco del motivo", "Hook", "Hook II", "Note guida", "Arpeggio melodico"]

    public static func suggest(genre g: Genre, recorded rec: [RecordedNote], totalSteps: Int,
                               fixedKey: Key? = nil, seed: Int = 0) -> InspirationResult {
        let total = max(16, totalSteps)
        let bars = (total + 15) / 16
        var hist = [Double](repeating: 0, count: 12)
        for n in rec { hist[mod12(n.note)] += Double(max(1, n.length)) }
        let key = fixedKey ?? KeyDetector.detect(histogram: hist, minorBias: g.prefersMinor ? 0.04 : -0.02) ?? g.defaultKey
        let scaleType = g.scale(for: key)
        let scale = key.scale(scaleType)
        let pk = g.progressionKey(for: key)
        let helper = SuggestionEngine(genre: g)
        helper.complexity = .genre
        var pool = helper.diatonicChords(key: key, scale: scaleType)
        for p in g.progressions { for rc in p.chords { let c = rc.chord(in: pk); if !pool.contains(c) { pool.append(c) } } }
        var chords: [Chord] = []
        var prev = Chord(root: key.tonic, quality: key.isMinor ? .minor : .major)
        for b in 0..<bars {
            var w = [Double](repeating: 0, count: 12)
            var low = 999
            for n in rec {
                let ov = min(n.step + n.length, (b + 1) * 16) - max(n.step, b * 16)
                if ov > 0 { w[mod12(n.note)] += Double(ov); low = min(low, n.note) }
            }
            if w.allSatisfy({ $0 == 0 }) { chords.append(prev); continue }
            var best = prev, bs = -1e9
            for c in pool {
                let cp = c.pitchClasses
                var sc = 0.0
                for pc in 0..<12 { sc += cp.contains(pc) ? w[pc] : -0.5 * w[pc] }
                if low < 999 && mod12(low) == c.root { sc += 2 }
                if sc > bs { bs = sc; best = c }
            }
            chords.append(best); prev = best
        }
        var top = [RecordedNote?](repeating: nil, count: total)
        var onsets = [Bool](repeating: false, count: total)
        for n in rec where n.step >= 0 && n.step < total {
            onsets[n.step] = true
            if top[n.step] == nil || n.note > top[n.step]!.note { top[n.step] = n }
        }
        let tops = top.compactMap { $0?.note }.sorted()
        let median = tops.isEmpty ? g.octave + 7 : tops[tops.count / 2]
        let center = median < 60 ? median + 12 : median + 3, lo = center - 9, hi = center + 12
        let notes = (lo...hi).filter { scale.contains(mod12($0)) }
        func near(_ n: Int, _ set: Set<Int>) -> Int {
            var b = n, d = 99
            for m in notes where set.contains(mod12(m)) && abs(m - n) < d { d = abs(m - n); b = m }
            return b
        }
        func stepScale(_ n: Int, _ k: Int) -> Int {
            let x = near(n, scale)
            let i = max(0, min(notes.count - 1, (notes.firstIndex(of: x) ?? 0) + k))
            return notes[i]
        }
        func chordAt(_ s: Int) -> Chord { chords[min(chords.count - 1, s / 16)] }
        let srcLine = (0..<total).compactMap { s in top[s].map { (s: s, note: $0.note, len: $0.length) } }
        let gi = Genre.all.firstIndex(of: g) ?? 0
        let style = Melodies.styles[g.id] ?? Melodies.Style(rhythms: [], rep: false, oct: false, chrom: false, blue: false, lift: 2, density: 1)
        let rpool = Melodies.pool(style).map { Array($0) }

        var options: [InspirationOption] = []
        for opt in 0..<10 {
            let s0 = (UInt32(truncatingIfNeeded: gi + 1) &* 7919 &+ UInt32(truncatingIfNeeded: 42 + opt) &* 31337
                      &+ UInt32(truncatingIfNeeded: opt + 1) &* 104729 &+ UInt32(truncatingIfNeeded: seed) &* 15485863)
                     ^ (UInt32(truncatingIfNeeded: rec.count) &* 2654435761)
            var R = SongRandom(s0)
            var mel: [(step: Int, note: Int, len: Int, vel: Int)] = []
            func push(_ step: Int, _ note: Int, _ len: Int, _ vel: Int) {
                if step >= 0 && step < total && note >= 21 && note <= 108 { mel.append((step, note, max(1, min(len, total - step)), vel)) }
            }
            switch opt {
            case 0, 1:      // counterpoint: fills the gaps, contrary motion
                let rh = rpool[(R.next(rpool.count) + opt * 5) % rpool.count]
                var n = near(center, chordAt(0).pitchClasses), lastSrc = -1
                for s in 0..<total where rh[s % 16] == "x" {
                    if onsets[s] && s % 4 != 0 && R.next(3) != 0 { continue }
                    var e = s + 1; while e < total && rh[e % 16] == "-" { e += 1 }
                    if let src = top[s], lastSrc >= 0 {
                        n = stepScale(n, src.note > lastSrc ? -1 - R.next(2) : src.note < lastSrc ? 1 + R.next(2) : (R.next(2) != 0 ? 1 : -1))
                    } else { n = stepScale(n, R.next(3) - 1) }
                    if let src = top[s] { lastSrc = src.note }
                    if s % 8 == 0 { n = near(n, chordAt(s).pitchClasses) }
                    if let src = top[s], [1, 2].contains(abs(n - src.note) % 12) { n = near(n + 3, chordAt(s).pitchClasses) }
                    push(s, n, e - s, s % 4 == 0 ? 96 : 82)
                }
            case 2, 3:      // parallel harmony a third / a sixth above the top line
                let k = opt == 2 ? 2 : 5
                for x in srcLine {
                    var n = x.note
                    for _ in 0..<k { n += 1; while !scale.contains(mod12(n)) { n += 1 } }
                    while n > hi + 5 { n -= 12 }
                    while n < lo { n += 12 }
                    push(x.s, n, x.len, 84)
                }
            case 4:         // call & response in the half-bars where the track rests
                for w in stride(from: 0, to: total, by: 8) {
                    let busy = (w..<min(total, w + 8)).contains { onsets[$0] }
                    if busy && !(w % 16 == 8 && R.next(2) == 0) { continue }
                    let motif = srcLine.filter { $0.s >= w - 8 && $0.s < w }
                    if motif.isEmpty {
                        var n = near(center, chordAt(w).pitchClasses)
                        for o in [0, 2, 4, 6] { push(w + o, n, 2, 84); n = stepScale(n, R.next(3) - 1) }
                    } else {
                        for m in motif {
                            let off = m.s - (w - 8)
                            push(w + off, near(stepScale(m.note, 2) + (m.note < lo ? 12 : 0), chordAt(w + off).pitchClasses), min(m.len, 8 - off), 86)
                        }
                    }
                }
            case 5:         // echo: an eighth later, an octave up
                for x in srcLine {
                    var n = x.note + 12
                    while n > hi + 5 { n -= 12 }
                    while n < lo { n += 12 }
                    push(x.s + 2, near(n, scale), max(1, x.len - 1), 72)
                }
            case 6, 7:      // hook on the track's own chords
                let ev = Melodies.events(genre: g, genreIndex: gi, key: key, chords: chords, arp: -1,
                                         melody: (opt * 7 + R.next(30)) % Melodies.count, seed: seed + opt, stepsPerChord: 16)
                for e in ev where e.velocity > 0 {
                    var len = 2
                    if let o = ev.first(where: { $0.velocity == 0 && $0.note == e.note && ($0.step > e.step || $0.step == 0) }) {
                        len = (o.step == 0 ? total : o.step) - e.step
                    }
                    push(e.step, Int(e.note), len, Int(e.velocity))
                }
            case 8:         // guide tones (3rds and 7ths)
                var n = center
                for s in stride(from: 0, to: total, by: 8) {
                    let c = chordAt(s), iv = c.quality.intervals
                    let guide: Set<Int> = [mod12(c.root + iv[1]), mod12(c.root + (iv.count > 3 ? iv[3] : iv[2]))]
                    n = near(n, guide); push(s, n, 8, 80)
                }
            default:        // melodic arpeggio in eighths
                for s in stride(from: 0, to: total, by: 2) {
                    let cp = chordAt(s).pitchClasses
                    let tones = notes.filter { cp.contains(mod12($0)) && $0 >= center - 3 && $0 <= center + 10 }
                    guard !tones.isEmpty else { continue }
                    let L = tones.count, period = max(1, L * 2 - 1), i = (s / 2) % period
                    let idx = i < L ? i : L * 2 - 2 - i
                    push(s, tones[max(0, idx)], 2, s % 4 == 0 ? 88 : 74)
                }
            }
            let sorted = mel.enumerated().sorted { $0.element.step != $1.element.step ? $0.element.step < $1.element.step : $0.offset < $1.offset }.map { $0.element }
            var events: [PatternEvent] = []
            for (i, m) in sorted.enumerated() {
                var end = m.step + m.len
                if i + 1 < sorted.count && sorted[i + 1].step < end { end = sorted[i + 1].step }
                if end <= m.step { continue }
                events.append(PatternEvent(step: m.step, note: UInt8(m.note), velocity: UInt8(m.vel), lane: 1))
                events.append(PatternEvent(step: end >= total ? 0 : end, note: UInt8(m.note), velocity: 0, lane: 1))
            }
            events = events.enumerated().sorted { a, b in
                if a.element.step != b.element.step { return a.element.step < b.element.step }
                let ao = a.element.velocity == 0, bo = b.element.velocity == 0
                return ao != bo ? ao : a.offset < b.offset
            }.map { $0.element }
            options.append(InspirationOption(name: names[opt], events: events))
        }
        return InspirationResult(key: key, chords: chords, options: options)
    }
}
