import Foundation

/// A note event in the genre player loop, expressed in 16th-note steps.
public struct PatternEvent: Equatable {
    public var step: Int
    public var note: UInt8
    public var velocity: UInt8   // 0 = note off
    public var lane: UInt8 = 0   // 0 = chords / bass, 1 = melody
}

public struct GenrePattern {
    public var events: [PatternEvent]   // sorted by step, offs before ons on the same step
    public var totalSteps: Int
    public var chords: [Chord]
    public var bpm: Double
}

/// Deterministic random numbers, identical to the web and desktop engines (mulberry32).
public struct SongRandom {
    var a: UInt32
    public init(_ seed: UInt32) { a = seed }
    public mutating func next(_ n: Int) -> Int {
        a = a &+ 0x6D2B79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Int((t ^ (t >> 14)) % UInt32(n))
    }
}

public enum Arpeggios {
    /// 30 arpeggio patterns: digit = chord tone (+ octave), c = whole chord, - = hold, . = rest.
    public static let all: [(name: String, steps: String)] = [
        ("Su","0123012301230123"), ("Giù","3210321032103210"), ("Su e giù","0123432101234321"),
        ("Alberti","0212021202120212"), ("Alberti lento","0.2.1.2.0.2.1.2."), ("Spezzato","0213021302130213"),
        ("Ottave","0303030303030303"), ("Pedale","0102010201020102"), ("Cascata","5432105432104321"),
        ("Salita lunga","0123456701234567"), ("Terzine","012012012012012-"), ("Rullo gospel","0123c---0123c---"),
        ("Stab in levare","..c...c...c...c."), ("Trance gate","c.c.c.c.c.c.c.c."), ("Dembow","c..c..c.c..c..c."),
        ("Charleston","c..c......c....."), ("Bossa","0.2..1.20.2..1.2"), ("Ballata","0---2---1---2---"),
        ("Arpa","0123456776543210"), ("Piano pop","0-2-1-2-c---c-2-"), ("Ostinato","0202020202020202"),
        ("Pulsante","c-c-c-c-c-c-c-c-"), ("Sincopato","c..c..c...c.c..."), ("Eco","0.0.2.2.1.1.3.3."),
        ("Scala di accordi","0-1-2-3-4-5-6-7-"), ("Minimal","0-------2-------"), ("Reggae skank","..c-..c-..c-..c-"),
        ("Funk stab","c.cc..c.c..c.c.."), ("Rotolante","0213243546352413"), ("Cinematico","0---1---2---3---")
    ]
}

public enum Melodies {
    public static let count = 30
    public static let names = ["Alba","Onda","Eco","Scintilla","Volo","Notte","Cometa","Respiro","Spirale","Orizzonte",
        "Ritornello","Danza","Riflesso","Sussurro","Vertigine","Marea","Lanterna","Brezza","Aurora","Galassia",
        "Fuoco","Neon","Miraggio","Tempesta","Cristallo","Satellite","Velluto","Fenice","Polvere di stelle","Eclissi"]

    static let rhythms = [
        "x-------x-------","x-----x-------..","x---x-------x---","x-------x---x---","x--x----x-------","x-----------x-x-",
        "x---x---x-x-x---","x-x---x-x---x---","x--x--x-x---x---","x---x-x---x-x---","x-x-x---x-------","..x-x-x-x---x---",
        "x--x--x---x-x---","x---x--x--x-x---",
        "x-x-x-x-x-x-x-x-","x-x-x-x-xxx-x---","x-xxx-x-x-xxx-x-","x.x.x.x.xx.xx.x.","xx-xx-x-xx-xx-x-","x-x-xx-xx-x-xx-x"]

    struct Style { var rhythms: [String]; var rep, oct, chrom, blue: Bool; var lift: Int; var density: Int }
    /// Hook rhythms and devices heard in each genre's hits.
    static let styles: [String: Style] = [
        "pop": Style(rhythms: ["x-x-x---x-x-x---","..x-x-x-x--x-x--","x--x--x-x-------","x-xx-x---x-x-x--"], rep: true, oct: true, chrom: false, blue: false, lift: 2, density: 1),
        "rock": Style(rhythms: ["x---x---x-x-x---","x-x-x-x-x---x---","x--x--x-x-x-----"], rep: false, oct: false, chrom: false, blue: true, lift: 2, density: 1),
        "hiphop": Style(rhythms: ["x--x--x---x-----","..x-x--x--x-x---","x-x--x--x-x-----"], rep: true, oct: false, chrom: false, blue: true, lift: 1, density: 1),
        "trap": Style(rhythms: ["x--x--x--x--x-x-","x-----x-x--x----","x--x--x---------"], rep: true, oct: false, chrom: false, blue: false, lift: 1, density: 0),
        "rnb": Style(rhythms: ["x-----x-x-x-----","..x---x-x--x----","x--x----x-x-x---"], rep: false, oct: false, chrom: true, blue: false, lift: 2, density: 0),
        "jazz": Style(rhythms: ["x--x-x--x--x-x--","..x-x-x-x-x--x--","x-x--x-x--x-x-x-"], rep: false, oct: false, chrom: true, blue: false, lift: 2, density: 2),
        "blues": Style(rhythms: ["x--x--x---x-----","..x--x-x--------","x-x--x--x-------"], rep: false, oct: false, chrom: false, blue: true, lift: 1, density: 1),
        "edm": Style(rhythms: ["x-x-x-x-x--x-x--","x--x--x-x--x--x-","xx-x-x-xx-x-x---"], rep: true, oct: true, chrom: false, blue: false, lift: 3, density: 2),
        "house": Style(rhythms: ["..x...x...x.x.x.","x--x--x---x-x---","..x-x-x-..x-x-x-"], rep: true, oct: false, chrom: false, blue: false, lift: 2, density: 2),
        "techno": Style(rhythms: ["x-x-x-x-x-x-x-x-","x--x--x-x--x--x-","x---x---x---x---"], rep: true, oct: false, chrom: false, blue: false, lift: 1, density: 2),
        "melodictechno": Style(rhythms: ["x-x-x-x-x---x---","x--x--x-x-------","x---x-x-x---x-x-"], rep: true, oct: true, chrom: false, blue: false, lift: 3, density: 1),
        "afrohouse": Style(rhythms: ["x..x..x...x.x...","..x..x..x.x.....","x..x.x..x..x...."], rep: true, oct: false, chrom: true, blue: false, lift: 2, density: 1),
        "reggaeton": Style(rhythms: ["x..x..x.x..x..x.","..x..x.x..x..x..","x..x..x.x-x-x---"], rep: true, oct: false, chrom: false, blue: false, lift: 2, density: 1),
        "latin": Style(rhythms: ["x..x..x...x.x...","x.x..x.x..x.x...","..x.x..x.x..x..."], rep: false, oct: false, chrom: true, blue: false, lift: 2, density: 2),
        "country": Style(rhythms: ["x-x-x---x-x-x---","x---x-x-x-------","..x-x-x-x---x---"], rep: false, oct: false, chrom: false, blue: false, lift: 2, density: 1),
        "funk": Style(rhythms: ["x.xx.x..x.x.xx..","..x.xx.x..x.x.x.","x..x.x..xx.x...."], rep: true, oct: false, chrom: true, blue: true, lift: 1, density: 2),
        "gospel": Style(rhythms: ["x-----x-x-x-----","x--x--x-x-----x-","..x-x-x-x-------"], rep: false, oct: false, chrom: true, blue: true, lift: 3, density: 0),
        "metal": Style(rhythms: ["xxx-xxx-xxx-xx-x","x-x-x-x-xx-xx-x-","x-xxx-xxx-x-x---"], rep: false, oct: true, chrom: false, blue: false, lift: 2, density: 2),
        "reggae": Style(rhythms: ["....x-x.....x-x.","x---..x-x---..x-","..x-x---..x-x---"], rep: true, oct: false, chrom: false, blue: false, lift: 1, density: 1),
        "classical": Style(rhythms: ["x-x-x-x-x---x---","x---x-x-x-x-x---","x-xxx-x-x-------"], rep: false, oct: false, chrom: true, blue: false, lift: 2, density: 2),
        "lofi": Style(rhythms: ["x-----x---x-----","..x---x-x-------","x---x-------x-x-"], rep: false, oct: false, chrom: true, blue: false, lift: 1, density: 0),
        "afrobeats": Style(rhythms: ["x..x..x.x.x..x..","..x..x..x.x.x...","x..x.x..x..x.x.."], rep: true, oct: false, chrom: false, blue: false, lift: 2, density: 2),
        "cinematic": Style(rhythms: ["x-------x---x---","x-----------x---","x---x---x-------"], rep: false, oct: true, chrom: false, blue: false, lift: 3, density: 0)
    ]
    static let contours: [[Int]] = [[0,1,2,3,4,3,2,1],[0,0,1,2,2,3,4,5],[5,4,4,3,2,1,1,0],[0,2,1,3,2,4,3,1],
        [0,3,1,4,2,5,1,0],[2,2,3,2,2,1,2,2],[0,2,4,2,1,3,5,3],[0,4,1,5,2,4,0,3],[4,4,4,2,3,3,3,1],[0,0,4,4,3,2,1,0]]

    static func pool(_ st: Style) -> [String] {
        let idx: [Int]
        switch st.density {
        case 0: idx = [0,1,2,3,4,5, 6,7,8,9]
        case 1: idx = [6,7,8,9,10,11,12,13, 0,1,2]
        default: idx = [14,15,16,17,18,19, 9,10,11,12,13]
        }
        return st.rhythms + st.rhythms + idx.map { rhythms[$0] }
    }

    /// Hook-based melody: 2-bar motif in an A A' B A form, chorus lifted, strong beats on chord tones.
    static func events(genre g: Genre, genreIndex gi: Int, key pk: Key, chords: [Chord], arp: Int, melody: Int,
                       seed: Int, stepsPerChord spc: Int) -> [PatternEvent] {
        let s0 = UInt32(truncatingIfNeeded: gi + 1) &* 7919 &+ UInt32(truncatingIfNeeded: arp + 2) &* 31337
            &+ UInt32(truncatingIfNeeded: melody + 1) &* 104729 &+ UInt32(truncatingIfNeeded: seed) &* 15485863
        var R = SongRandom(s0)
        let st = styles[g.id] ?? Style(rhythms: [], rep: false, oct: false, chrom: false, blue: false, lift: 2, density: 1)
        let scale = pk.scale(g.scale(for: pk))
        let center = g.octave + 10, lo = center - 9, hi = center + 14
        let notes = (lo...hi).filter { scale.contains(mod12($0)) }
        var base = 0
        for i in notes.indices where abs(notes[i] - (center - 3)) < abs(notes[base] - (center - 3)) { base = i }
        let pl = pool(st), P = pl.count
        let rA = Array(pl[(melody * 3 + R.next(P)) % P]), rB = Array(pl[(melody * 7 + 2 + R.next(P)) % P])
        let cA = contours[(melody + R.next(10)) % 10], cB = contours[(melody * 3 + 1 + R.next(10)) % 10]
        let lift = st.lift, reg = R.next(3) - 1
        let repHook = st.rep && R.next(3) != 0
        let sig = g.signatureNotes.map { mod12(pk.tonic + $0) }
        let blue = [mod12(pk.tonic + 3), mod12(pk.tonic + 6), mod12(pk.tonic + 10)]
        let total = spc * chords.count, N = notes.count
        func clampIdx(_ i: Int) -> Int { max(0, min(N - 1, i)) }
        func nearestChordTone(_ n: Int, _ cp: Set<Int>) -> Int {
            var best = n, bd = 99
            for m in notes where cp.contains(mod12(m)) && abs(m - n) < bd { bd = abs(m - n); best = m }
            return best
        }
        var ev: [PatternEvent] = []
        var prev = -1
        for b in 0..<(total / 16) {
            let ci = b * 16 / spc, chordPcs = chords[ci].pitchClasses
            let phrase = (b / 2) % 4, inPhrase = b % 2
            let isB = phrase == 2, rhythm = isB ? rB : rA, contour = isB ? cB : cA
            let shift = reg + (isB ? lift : 0) + (phrase == 1 && inPhrase == 1 ? -1 : 0)
            let starts = (0..<16).filter { rhythm[$0] == "x" }
            for (k, s) in starts.enumerated() {
                var e = s + 1; while e < 16 && rhythm[e] == "-" { e += 1 }
                let pos = inPhrase * 4 + s / 4
                var idx = clampIdx(base + contour[pos] + shift)
                if repHook && inPhrase == 0 && k > 0 && k < 3 { idx = clampIdx(base + contour[0] + shift) }
                var n = notes[idx]
                if s % 8 == 0 || k == 0 { n = nearestChordTone(n, chordPcs) }
                else if st.blue && R.next(5) == 0 {
                    if let bn = [n - 1, n + 1, n - 2].first(where: { blue.contains(mod12($0)) && $0 >= lo && $0 <= hi }) { n = bn }
                } else if R.next(6) == 0 {
                    let near = notes.filter { sig.contains(mod12($0)) && abs($0 - n) <= 3 }
                    if !near.isEmpty { n = near[R.next(near.count)] }
                }
                if st.oct && isB && inPhrase == 0 && k == 0 && n + 12 <= hi + 5 { n += 12 }
                if n == prev && !(repHook && inPhrase == 0) && R.next(2) == 0 {
                    let j = (notes.firstIndex(of: n) ?? -1) + (R.next(2) != 0 ? 1 : -1)
                    if j >= 0 && j < N { n = notes[j] }
                }
                let next: Int? = k + 1 < starts.count ? starts[k + 1] : nil
                if st.chrom, let nx = next, nx % 8 == 0, e - s >= 2, R.next(3) == 0 {
                    let target = nearestChordTone(notes[clampIdx(base + contour[inPhrase * 4 + nx / 4] + shift)], chordPcs)
                    let mid = s + max(1, (e - s) / 2)
                    let ap = target - 1, stop = b * 16 + e
                    ev.append(PatternEvent(step: b * 16 + s, note: UInt8(n), velocity: 92, lane: 1))
                    ev.append(PatternEvent(step: b * 16 + mid, note: UInt8(n), velocity: 0, lane: 1))
                    ev.append(PatternEvent(step: b * 16 + mid, note: UInt8(ap), velocity: 78, lane: 1))
                    ev.append(PatternEvent(step: stop >= total ? 0 : stop, note: UInt8(ap), velocity: 0, lane: 1))
                    prev = ap
                    continue
                }
                let start = b * 16 + s, stop = b * 16 + e
                let vel = (s % 4 == 0 ? 100 : 82) + R.next(9) - 4
                ev.append(PatternEvent(step: start, note: UInt8(n), velocity: UInt8(vel), lane: 1))
                ev.append(PatternEvent(step: stop >= total ? 0 : stop, note: UInt8(n), velocity: 0, lane: 1))
                prev = n
            }
        }
        return ev
    }
}

/// Turns a genre progression + rhythm (or one of 30 arpeggios) + optional melody into a loop of MIDI events.
public enum GenrePatternBuilder {
    public static func build(genre: Genre, key: Key, progressionIndex: Int = 0,
                             complexity: ChordComplexity = .genre, arpeggio: Int = -1, melody: Int = -1,
                             seed: Int = 0) -> GenrePattern {
        let pKey = genre.progressionKey(for: key)
        let prog = genre.progressions[max(0, min(progressionIndex, genre.progressions.count - 1))]
        let engine = SuggestionEngine(genre: genre)
        engine.complexity = complexity
        let chords = prog.chords.map { engine.adjust($0.chord(in: pKey)) }
        let arpSteps: [Character]? = arpeggio >= 0 && arpeggio < Arpeggios.all.count ? Array(Arpeggios.all[arpeggio].steps) : nil

        let chordSteps = Array(genre.chordRhythm)
        let bassSteps = Array(genre.bassRhythm)
        let stepsPerChord = 16 * max(1, genre.barsPerChord)
        let total = stepsPerChord * chords.count
        var events: [PatternEvent] = []

        var previousVoicing: [Int] = []
        for (ci, chord) in chords.enumerated() {
            let voicing = chord.voicing(near: genre.octave, previous: previousVoicing, withBass: false)
            previousVoicing = voicing
            let ext = Array((voicing + voicing.map { $0 + 12 }).prefix(8))
            let arpOrder = arpeggioOrder(count: voicing.count)
            var bassRoot = (voicing.first ?? 48) / 12 * 12 + chord.root
            // Keep the whole bass lane (root, fifth, octave) strictly below the chord voicing.
            while bassRoot + 12 >= (voicing.first ?? 48) { bassRoot -= 12 }
            if bassRoot < 24 { bassRoot += 12 }
            let iv = chord.quality.intervals
            let fifthOffset = iv.contains(7) ? 7 : (iv.contains(6) ? 6 : (iv.contains(8) ? 8 : 7))

            var chordOn: [Int] = []
            var bassOn: Int?
            var arpIndex = 0
            func offAll(_ step: Int) {
                for n in chordOn { events.append(PatternEvent(step: step, note: UInt8(n), velocity: 0)) }
                chordOn = []
            }
            for s in 0..<stepsPerChord {
                let step = ci * stepsPerChord + s
                let b = bassSteps[s % 16]
                if let arp = arpSteps {
                    let c = arp[s % 16]
                    if c == "c" {
                        offAll(step); chordOn = voicing
                        for n in voicing { events.append(PatternEvent(step: step, note: UInt8(n), velocity: s % 4 == 0 ? 100 : 80)) }
                    } else if let d = c.wholeNumberValue {
                        offAll(step)
                        let n = ext[d % ext.count]; chordOn = [n]
                        events.append(PatternEvent(step: step, note: UInt8(n), velocity: s % 4 == 0 ? 96 : 74))
                    } else if c == "." { offAll(step) }
                } else {
                    let c = chordSteps[s % 16]
                    switch c {
                    case "x", "o":
                        offAll(step); chordOn = voicing
                        for n in voicing { events.append(PatternEvent(step: step, note: UInt8(n), velocity: c == "x" ? 104 : 78)) }
                    case "a":
                        offAll(step)
                        let n = voicing[arpOrder[arpIndex % arpOrder.count]]
                        arpIndex += 1; chordOn = [n]
                        events.append(PatternEvent(step: step, note: UInt8(n), velocity: arpIndex % 4 == 1 ? 92 : 72))
                    case ".": offAll(step)
                    default: break
                    }
                }
                switch b {
                case "x", "f", "o":
                    if let n = bassOn { events.append(PatternEvent(step: step, note: UInt8(n), velocity: 0)) }
                    let n = b == "x" ? bassRoot : (b == "f" ? bassRoot + fifthOffset : bassRoot + 12)
                    bassOn = n
                    events.append(PatternEvent(step: step, note: UInt8(n), velocity: b == "x" ? 100 : 84))
                case ".":
                    if let n = bassOn { events.append(PatternEvent(step: step, note: UInt8(n), velocity: 0)) }
                    bassOn = nil
                default: break
                }
            }
            let end = (ci + 1) * stepsPerChord
            let endStep = end == total ? 0 : end
            offAll(endStep)
            if let n = bassOn { events.append(PatternEvent(step: endStep, note: UInt8(n), velocity: 0)) }
        }
        if melody >= 0 {
            let gi = Genre.all.firstIndex(of: genre) ?? 0
            events += Melodies.events(genre: genre, genreIndex: gi, key: pKey, chords: chords, arp: arpeggio,
                                      melody: melody % Melodies.count, seed: seed, stepsPerChord: stepsPerChord)
        }
        // Stable sort: by step, note-offs first so re-triggered notes are not cut.
        events = events.enumerated().sorted { a, b in
            if a.element.step != b.element.step { return a.element.step < b.element.step }
            let ao = a.element.velocity == 0, bo = b.element.velocity == 0
            if ao != bo { return ao }
            return a.offset < b.offset
        }.map { $0.element }
        return GenrePattern(events: events, totalSteps: total, chords: chords, bpm: genre.bpm)
    }

    static func arpeggioOrder(count: Int) -> [Int] {
        switch count {
        case 0, 1: return [0]
        case 2: return [0, 1]
        case 3: return [0, 2, 1, 2]           // Alberti bass style
        default: return [0, 2, 1, 3]
        }
    }
}
