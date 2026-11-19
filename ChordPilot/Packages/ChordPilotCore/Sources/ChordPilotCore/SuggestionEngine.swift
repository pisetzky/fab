import Foundation

public enum ChordComplexity: Int, CaseIterable, Codable {
    case simple = 0     // triads only
    case genre = 1      // as the genre writes them
    case rich = 2       // add 7ths / 9ths

    public var displayName: String {
        switch self {
        case .simple: return "Semplici"
        case .genre: return "Del genere"
        case .rich: return "Ricchi"
        }
    }
}

/// Role of a key on the keyboard in the current suggestion.
public enum HighlightRole: Int, Comparable {
    case scale = 0          // safe note of the scale
    case signature = 1      // characteristic genre colour note
    case melody = 2         // suggested next melody note
    case alternative = 3    // tone of an alternative next chord
    case primary = 4        // tone of the best next chord

    public static func < (a: HighlightRole, b: HighlightRole) -> Bool { a.rawValue < b.rawValue }
}

public struct KeyHighlight: Equatable {
    public var role: HighlightRole
    public var strength: Double      // 0...1
    public var rank: Int             // 0 = best suggestion
}

public struct ChordSuggestion: Identifiable, Equatable {
    public var id: String { chord.name() + "_" + String(rank) }
    public var chord: Chord
    public var roman: String
    public var score: Double
    public var rank: Int
    public var voicing: [Int]
    public var reason: String
    public var displayName: String
}

public struct SuggestionResult: Equatable {
    public var currentChord: Chord?
    public var currentChordName: String?
    public var key: Key
    public var scale: ScaleType
    public var chords: [ChordSuggestion]
    public var highlights: [Int: KeyHighlight]   // MIDI note → highlight
    public var melodyNotes: [Int]

    public static func empty(_ key: Key) -> SuggestionResult {
        SuggestionResult(currentChord: nil, currentChordName: nil, key: key, scale: .major,
                         chords: [], highlights: [:], melodyNotes: [])
    }
}

/// The brain of ChordPilot: listens to what you play and lights up what could come next.
public final class SuggestionEngine {
    public var genre: Genre
    public var complexity: ChordComplexity = .genre
    /// nil = detect the key automatically from what is played.
    public var fixedKey: Key?
    public var maxSuggestions = 6
    /// Keyboard range used for highlights.
    public var lowNote = 36
    public var highNote = 96

    private(set) public var history: [Chord] = []
    private var pitchHistogram = [Double](repeating: 0, count: 12)
    private var lastVoicing: [Int] = []

    public init(genre: Genre = Genre.all[0]) {
        self.genre = genre
    }

    // MARK: Key

    public var currentKey: Key {
        if let k = fixedKey { return k }
        let total = pitchHistogram.reduce(0, +)
        guard total > 2 else { return genre.defaultKey }
        return KeyDetector.detect(histogram: pitchHistogram, minorBias: genre.prefersMinor ? 0.04 : -0.02)
            ?? genre.defaultKey
    }

    public func reset() {
        history.removeAll()
        pitchHistogram = [Double](repeating: 0, count: 12)
        lastVoicing = []
    }

    /// Feed every note-on here so the automatic key detection learns.
    public func registerNoteOn(_ note: Int, velocity: Int = 100) {
        // Exponential decay keeps the key estimate focused on recent playing.
        for i in 0..<12 { pitchHistogram[i] *= 0.985 }
        pitchHistogram[mod12(note)] += 0.5 + Double(velocity) / 254.0
    }

    /// Call when a chord is recognised and held (or when a suggestion is played) to update the context.
    public func commit(chord: Chord) {
        if let last = history.last, last.isLooselyEqual(chord) { return }
        history.append(chord)
        if history.count > 8 { history.removeFirst(history.count - 8) }
        for pc in chord.pitchClasses { pitchHistogram[pc] += 0.6 }
    }

    // MARK: Suggestions

    public func suggest(held: [Int]) -> SuggestionResult {
        let key = currentKey
        let pKey = genre.progressionKey(for: key)
        let scaleType = genre.scale(for: key)
        let scalePCs = key.scale(scaleType)
        let heldSorted = held.sorted()
        let current = ChordDetector.detect(heldSorted)
        let context: Chord? = current ?? history.last

        // Candidate pool: every chord the genre uses in this key, plus diatonic chords.
        var pool: [Chord: (roman: String, base: Double)] = [:]
        for prog in genre.progressions {
            for rc in prog.chords {
                let c = adjust(rc.chord(in: pKey))
                let existing = pool[c]?.base ?? 0
                pool[c] = (rc.symbol, max(existing, 0.4 * prog.weight))
            }
        }
        for c in diatonicChords(key: key, scale: scaleType) where pool[c] == nil {
            pool[c] = (RomanChord.label(for: c, in: key), 0.15)
        }

        // The chord played before the context chord, for two-chord pattern matching.
        let prior: Chord? = {
            guard let ctx = context else { return nil }
            if let last = history.last, last.isLooselyEqual(ctx) {
                return history.count >= 2 ? history[history.count - 2] : nil
            }
            return history.last
        }()
        var scored: [(Chord, Double, String, String)] = []   // chord, score, roman, reason
        let melodyNote = heldSorted.count == 1 ? mod12(heldSorted[0]) : nil

        for (cand, info) in pool {
            var score = info.base
            var reason = "Tipico del \(genre.name)"

            if let ctx = context {
                if cand.isLooselyEqual(ctx) { score -= 3 }   // don't suggest what you're already playing
                // Progression knowledge: what usually follows the context chord in this genre?
                for prog in genre.progressions {
                    let chords = prog.chords.map { adjust($0.chord(in: pKey)) }
                    guard chords.count > 1 else { continue }
                    for i in 0..<chords.count where chords[i].isLooselyEqual(ctx) {
                        let next = chords[(i + 1) % chords.count]
                        if next.isLooselyEqual(cand) {
                            score += 3.0 * prog.weight
                            reason = "Progressione \(genre.name): " + prog.chords.map { $0.symbol }.joined(separator: "–")
                            // Bonus if the chord before also matches (longer context).
                            if let prevCtx = prior {
                                let prevIdx = (i - 1 + chords.count) % chords.count
                                if chords[prevIdx].isLooselyEqual(prevCtx) { score += 1.5 * prog.weight }
                            }
                        }
                    }
                }
                // Functional harmony: strong root motions.
                let motion = mod12(cand.root - ctx.root)
                switch motion {
                case 5: score += 0.9          // up a fourth (V→I, ii→V)
                case 7: score += 0.5          // up a fifth
                case 2, 10: score += 0.35     // step
                case 3, 4, 8, 9: score += 0.25 // third relations
                default: break
                }
                // Voice-leading: common tones make a smooth change.
                score += 0.18 * Double(cand.pitchClasses.intersection(ctx.pitchClasses).count)
            } else if mod12(cand.root - pKey.tonic) == 0 {
                score += 1.0
                reason = "Accordo di tonica"
            }

            if let m = melodyNote {
                // Melodic note held: prefer chords that harmonise it.
                if cand.pitchClasses.contains(m) {
                    score += 2.2
                    if cand.root == m { score += 0.4 }
                    reason = "Armonizza la nota \(NoteName.name(m, flats: key.prefersFlats))"
                } else { score -= 1.5 }
            }
            // Out-of-scale chords are allowed (genre colour) but slightly penalised.
            let outside = cand.pitchClasses.subtracting(scalePCs).count
            score -= 0.12 * Double(outside)

            scored.append((cand, score, info.roman, reason))
        }

        scored.sort { $0.1 == $1.1 ? $0.0.name() < $1.0.name() : $0.1 > $1.1 }
        let center = heldSorted.isEmpty ? genre.octave : max(48, min(72, heldSorted.reduce(0, +) / heldSorted.count))
        var suggestions: [ChordSuggestion] = []
        var previous = heldSorted.count > 1 ? heldSorted : lastVoicing
        for (rank, item) in scored.prefix(maxSuggestions).enumerated() {
            let voicing = item.0.voicing(near: center, previous: previous, withBass: false)
            if rank == 0 { previous = voicing }
            suggestions.append(ChordSuggestion(
                chord: item.0, roman: RomanChord.label(for: item.0, in: key), score: item.1, rank: rank,
                voicing: voicing, reason: item.3, displayName: item.0.name(flats: key.prefersFlats)))
        }

        // Keyboard highlights.
        var highlights: [Int: KeyHighlight] = [:]
        func mark(_ note: Int, _ role: HighlightRole, _ strength: Double, _ rank: Int) {
            guard note >= lowNote && note <= highNote else { return }
            if let e = highlights[note], e.role >= role { return }
            highlights[note] = KeyHighlight(role: role, strength: strength, rank: rank)
        }
        for n in lowNote...highNote {
            let pc = mod12(n)
            if scalePCs.contains(pc) { mark(n, .scale, 0.18, 99) }
            if genre.signatureNotes.contains(where: { mod12(key.tonic + $0) == pc }) && scalePCs.contains(pc) {
                mark(n, .signature, 0.3, 99)
            }
        }
        let melody = melodyHints(held: heldSorted, key: key, scalePCs: scalePCs, scaleType: scaleType,
                                 next: suggestions.first?.chord)
        for n in melody { mark(n, .melody, 0.55, 50) }
        for s in suggestions.dropFirst().prefix(2) {
            for n in s.voicing { mark(n, .alternative, s.rank == 1 ? 0.6 : 0.45, s.rank) }
        }
        if let best = suggestions.first {
            for n in best.voicing { mark(n, .primary, 1.0, 0) }
            // Also show the root an octave below as a bass suggestion.
            if let low = best.voicing.first {
                var b = (low / 12) * 12 + best.chord.root
                while b >= low { b -= 12 }
                mark(b, .primary, 0.8, 0)
            }
        }

        return SuggestionResult(currentChord: current, currentChordName: current?.name(flats: key.prefersFlats),
                                key: key, scale: scaleType, chords: suggestions,
                                highlights: highlights, melodyNotes: melody)
    }

    /// Genius mode: turns any key into the closest note that fits the song and picks the next chord
    /// that harmonises it while continuing the progression.
    // MARK: Melodic brain (same rules as the web and desktop engines)

    struct MelState { var phrase: [Int] = []; var count = 0; var pressed: Int? = nil; var prevNote: Int? = nil; var last: Double = -1e12 }
    var mel = MelState()

    /// Reads the pressed key as an intention (up / down / same, small or big) and returns the most musical next note:
    /// short steps, leaps answered by a step back, singing range, leading tone → home, notes with good continuations,
    /// 8-note phrases whose second half answers the motif and ends at home. A pause > 1.8 s starts a new phrase.
    public func melodicNote(_ pressed: Int, now: Double? = nil, commit: Bool = true) -> Int {
        let key = currentKey
        let scale = key.scale(genre.scale(for: key))
        var phrase = mel.phrase, count = mel.count
        if let t = now, t - mel.last > 1800 { phrase = []; count = 0 }
        if count % 8 == 0 { phrase = [] }
        let idx = count % 8
        let ctx = suggest(held: [])
        let nextChord = ctx.chords.first?.chord.pitchClasses ?? [key.tonic]
        let tonicChord = Chord(root: key.tonic, quality: key.isMinor ? .minor : .major).pitchClasses
        let center = genre.octave + 10
        let prev = phrase.last ?? mel.prevNote
        var best = pressed, bs = -1e9
        if let prev = prev {
            let gest = mel.pressed.map { pressed - $0 } ?? 0
            let dir = gest.signum(), size = abs(gest)
            let want: Double = size == 0 ? 0 : size <= 3 ? 1.5 : size <= 7 ? 3 : 4.5
            let lastIv = phrase.count >= 2 ? prev - phrase[phrase.count - 2] : 0
            var target: Int? = nil
            if idx == 4, let first = phrase.first { target = first }
            else if idx > 4 && phrase.count >= idx { target = prev + (phrase[idx - 4] - phrase[idx - 5]) }
            for c in (prev - 9)...(prev + 9) where scale.contains(mod12(c)) {
                let iv = c - prev, a = abs(iv)
                var sc = 0.0
                let intent = idx == 7 ? 0.35 : 1.0
                if dir != 0 { sc += intent * (iv.signum() == dir ? 2 : iv == 0 ? -1 : -3); sc -= intent * 0.5 * abs(Double(a) - want) }
                else { sc += iv == 0 ? 1 : -0.4 * Double(a) }
                sc += a <= 2 ? 2.5 : a <= 4 ? 1 : a <= 7 ? -0.8 : -3
                if abs(lastIv) > 4 {
                    if iv.signum() == -lastIv.signum() && a <= 2 { sc += 2 } else if iv.signum() == lastIv.signum() && a > 2 { sc -= 2 }
                }
                if let tg = target { sc += c == tg ? 3 : -0.6 * Double(abs(c - tg)) }
                if nextChord.contains(mod12(c)) { sc += 1.5 }
                if idx == 7 { sc += mod12(c) == key.tonic ? 8 : tonicChord.contains(mod12(c)) ? 2 : 0 }
                if idx == 6 { let r = mod12(c - key.tonic); if min(r, 12 - r) <= 2 { sc += 1.5 } }
                if mod12(prev - key.tonic) == 11 && mod12(c - key.tonic) == 0 && iv > 0 { sc += 3 }
                sc -= Double(max(0, abs(c - center) - 7))
                if phrase.count >= 2 && c == prev && prev == phrase[phrase.count - 2] { sc -= 3 }
                var options = 0
                for d in -4...4 where d != 0 && scale.contains(mod12(c + d)) {
                    if ctx.chords.prefix(4).contains(where: { $0.chord.pitchClasses.contains(mod12(c + d)) }) { options += 1 }
                }
                sc += 0.2 * Double(options)
                sc -= 0.08 * Double(abs(c - pressed))
                if sc > bs { bs = sc; best = c }
            }
        } else {
            for c in (pressed - 7)...(pressed + 7) where tonicChord.contains(mod12(c)) {
                let sc = -Double(abs(c - pressed)) - 1.2 * Double(max(0, abs(c - center) - 4)) + (mod12(c) == key.tonic ? 0.5 : 0)
                if sc > bs { bs = sc; best = c }
            }
        }
        if commit {
            phrase.append(best)
            mel.phrase = phrase; mel.count = count + 1; mel.pressed = pressed; mel.prevNote = best
            if let t = now { mel.last = t }
        }
        return best
    }

    /// Records a note chosen by the real-time engine into the melodic memory.
    public func melodicCommit(pressed: Int, note: Int, now: Double? = nil) {
        if let t = now, t - mel.last > 1800 { mel.phrase = []; mel.count = 0 }
        if mel.count % 8 == 0 { mel.phrase = [] }
        mel.phrase.append(note); mel.count += 1; mel.pressed = pressed; mel.prevNote = note
        if let t = now { mel.last = t }
    }

    public func genius(note: Int, now: Double? = nil, commit: Bool = true) -> (note: Int, chord: Chord, shift: Int) {
        let key = currentKey
        let ctx = suggest(held: [])
        let m = melodicNote(note, now: now, commit: commit)
        // Cadence: a phrase that closes on the tonic is harmonised with the home chord.
        let closing = (commit ? mel.count : mel.count + 1) % 8 == 0
        if closing && mod12(m) == key.tonic {
            var home = Chord(root: key.tonic, quality: key.isMinor ? .minor : .major)
            if Self.richGenres.contains(genre.id) && complexity != .simple { home = Chord(root: home.root, quality: Self.enrich(home.quality)) }
            if !(history.last.map { home.isLooselyEqual($0) } ?? false) { return (m, home, m - note) }
        }
        let pc = mod12(m)
        // Every note gets its own chord: the best next chord containing the note, never the chord just played.
        let last = history.last
        func fresh(_ s: ChordSuggestion) -> Bool { s.chord.pitchClasses.contains(pc) && !(last.map { s.chord.isLooselyEqual($0) } ?? false) }
        var pick = ctx.chords.first(where: fresh)?.chord
        if pick == nil { pick = suggest(held: [m]).chords.first(where: fresh)?.chord }
        if pick == nil { pick = ctx.chords.first(where: { $0.chord.pitchClasses.contains(pc) })?.chord }
        var ch = pick ?? Chord(root: key.tonic, quality: key.isMinor ? .minor : .major)
        if Self.richGenres.contains(genre.id) && complexity != .simple { ch = Chord(root: ch.root, quality: Self.enrich(ch.quality)) }
        return (m, ch, m - note)
    }

    // MARK: Pro options (inspired by Scaler, Captain Chords, InstaChord/Cthulhu)

    public static let voicingStyles = ["Automatico", "Stretto", "Aperto", "Drop 2", "Largo"]

    /// One-finger chords: the chord of the scale built on each pitch class
    /// (black keys: a richer version of the nearest lower degree).
    public func oneFingerTable() -> [(root: Int, quality: ChordQuality, tones: [Int])] {
        let key = currentKey
        let chords = diatonicChords(key: key, scale: genre.scale(for: key))
        return (0..<12).map { pc in
            var c: Chord
            if let found = chords.first(where: { $0.root == pc }) { c = found }
            else {
                let lower = chords.filter { mod12(pc - $0.root) <= 2 }.min { mod12(pc - $0.root) < mod12(pc - $1.root) } ?? chords.first
                    ?? Chord(root: key.tonic, quality: .major)
                c = Chord(root: lower.root, quality: Self.enrich(lower.quality))
            }
            var tones: [Int] = []
            for iv in c.quality.intervals where !tones.contains(mod12(c.root + iv)) { tones.append(mod12(c.root + iv)) }
            return (c.root, c.quality, tones)
        }
    }

    /// Scale lock: closest note of the current scale (ties go down).
    public func lockToScale(_ note: Int) -> Int {
        let key = currentKey
        let sc = key.scale(genre.scale(for: key))
        for d in [0, -1, 1, -2, 2] where sc.contains(mod12(note + d)) { return note + d }
        return note
    }

    /// Chord tones stacked on `rootNote` in a style (1 Stretto, 2 Aperto, 3 Drop 2, 4 Largo), plus the bass.
    public static func styleVoicing(tones: [Int], root: Int, rootNote: Int, style: Int) -> [Int] {
        var r = rootNote
        while mod12(r) != root { r -= 1 }
        let order = [root] + tones.filter { $0 != root }
        var notes: [Int] = []
        var last = r - 1
        for t in order { var n = last + 1; while mod12(n) != t { n += 1 }; notes.append(n); last = n }
        if style == 2 && notes.count >= 3 { notes[1] += 12 }
        if style == 3 && notes.count >= 4 { notes[notes.count - 2] -= 12 }
        if style == 4 { for i in 1..<notes.count { notes[i] += 12 } }
        notes.append(r - 12)
        return Array(Set(notes.filter { $0 >= 21 && $0 <= 108 })).sorted()
    }

    // MARK: Pianist mode & two hands

    public private(set) var geniusMelody: [Int] = []
    public func geniusPlayed(_ note: Int) { geniusMelody.append(note); if geniusMelody.count > 8 { geniusMelody.removeFirst() } }

    /// Suggested next melody notes in Genius mode, each with the chord it will produce (hit-melody rules:
    /// short steps, a leap answered by a step back, sequences, phrase endings that resolve home).
    public func geniusNext() -> [(note: Int, chord: Chord)] {
        let key = currentKey
        let scale = key.scale(genre.scale(for: key))
        let mel = geniusMelody
        let prev = self.mel.prevNote ?? mel.last ?? genre.octave + 7
        let ctx = suggest(held: [])
        let last = history.last
        var out: [(note: Int, chord: Chord, score: Double)] = []
        for n in (prev - 7)...(prev + 7) where n != prev && scale.contains(mod12(n)) {
            let pc = mod12(n)
            guard let idx = ctx.chords.firstIndex(where: { $0.chord.pitchClasses.contains(pc) && !(last.map { l in $0.chord.isLooselyEqual(l) } ?? false) }) else { continue }
            var c = ctx.chords[idx].chord
            let d = abs(n - prev)
            var score = 10 - 1.5 * Double(idx)
            score += d <= 2 ? 3 : d <= 4 ? 2 : d == 5 ? 1 : d == 7 ? 0.5 : -1
            let rel = mod12(pc - c.root)
            if rel == 0 { score += 1 } else if rel == 3 || rel == 4 { score += 1.5 }
            if mel.count >= 2 {
                let lastIv = prev - mel[mel.count - 2]
                if abs(lastIv) > 4 && (n - prev).signum() == -lastIv.signum() && d <= 2 { score += 2 }
                if mel.count >= 3 && n - prev == mel[mel.count - 2] - mel[mel.count - 3] { score += 2 }
            }
            if mel.count % 4 == 3 && pc == key.tonic { score += 2.5 }
            if n > prev && mel.count % 4 == 1 { score += 0.5 }
            if Self.richGenres.contains(genre.id) && complexity != .simple { c = Chord(root: c.root, quality: Self.enrich(c.quality)) }
            out.append((n, c, score))
        }
        out.sort { $0.score > $1.score }
        var best: [(note: Int, chord: Chord)] = []
        for o in out where !best.contains(where: { $0.chord.root == o.chord.root && $0.chord.quality == o.chord.quality }) {
            best.append((o.note, o.chord)); if best.count == 3 { break }
        }
        return best
    }

    /// Two hands – left hand: the progression chord built on the pressed note.
    public func geniusLeft(_ note: Int) -> Chord {
        let key = currentKey
        let scale = key.scale(genre.scale(for: key))
        var m = note
        for d in [0, -1, 1, -2, 2] where scale.contains(mod12(note + d)) { m = note + d; break }
        let pc = mod12(m)
        let ctx = suggest(held: [])
        let last = history.last
        func fresh(_ s: ChordSuggestion) -> Bool { !(last.map { s.chord.isLooselyEqual($0) } ?? false) }
        var ch = ctx.chords.first(where: { fresh($0) && $0.chord.root == pc })?.chord
            ?? ctx.chords.first(where: { fresh($0) && $0.chord.pitchClasses.contains(pc) })?.chord
            ?? diatonicChords(key: key, scale: genre.scale(for: key)).first(where: { $0.root == pc })
            ?? Chord(root: pc, quality: key.isMinor ? .minor : .major)
        if Self.richGenres.contains(genre.id) && complexity != .simple { ch = Chord(root: ch.root, quality: Self.enrich(ch.quality)) }
        return ch
    }

    /// Left hand like a pianist: root at the pressed key's position + 3rd and 7th (or 3rd and 5th), within an octave, below `split`.
    public static func leftHandVoicing(_ c: Chord, pressed: Int, split: Int) -> [Int] {
        let iv = c.quality.intervals.map { $0 % 12 }
        var r = pressed + 2
        while mod12(r) != c.root { r -= 1 }
        while r + 11 >= split && r - 12 >= 28 { r -= 12 }
        let third = iv[1]
        let upper2 = iv.count > 3 && iv[3] > third ? iv[3] : iv[2]
        return [r, r + third, r + upper2].filter { $0 < split && $0 >= 24 }
    }

    /// Right hand: melody on top + up to two chord tones under it (3rd/7th first), within an octave, never below `split`.
    public static func rightHandVoicing(_ c: Chord, melody: Int, split: Int) -> [Int] {
        func rank(_ t: Int) -> Int {
            let r = mod12(t - c.root)
            return [3, 4, 10, 11].contains(r) ? 0 : [6, 7, 8].contains(r) ? 1 : r == 0 ? 3 : 2
        }
        let tones = Array(c.pitchClasses).filter { $0 != mod12(melody) }.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0 < $1 }
        var out = [melody]
        for pc in tones.prefix(2) { var n = melody - 1; while mod12(n) != pc { n -= 1 }; if n >= melody - 11 && n >= split { out.append(n) } }
        return out.sorted()
    }

    static let richGenres: Set<String> = ["jazz", "rnb", "gospel", "lofi", "latin", "house", "melodictechno", "afrohouse", "cinematic"]

    /// Pianist voicing: right hand = up to 3 chord tones just below the melody (3rd/7th first, then 5th, 9th, root);
    /// left hand = root in the bass plus fifth or octave.
    public static func geniusVoicing(tones: [Int], root: Int, melody: Int) -> [Int] {
        func rank(_ t: Int) -> Int {
            let r = mod12(t - root)
            if [3, 4, 10, 11].contains(r) { return 0 }
            if [6, 7, 8].contains(r) { return 1 }
            if [2, 5, 9].contains(r) { return 2 }
            return 3
        }
        let ordered = tones.filter { $0 != mod12(melody) }.enumerated()
            .sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }
            .prefix(3).map { $0.element }
        var rh: [Int] = []
        for pc in ordered { var n = melody - 1; while mod12(n) != pc { n -= 1 }; if n >= melody - 11 { rh.append(n) } }
        let low = rh.min() ?? melody
        var r = min(low - 3, 52)
        while mod12(r) != root { r -= 1 }
        if r < 28 { r += 12 }
        var lh = [r]
        if r + 7 < low - 2 { lh.append(r + 7) } else if r + 12 < low - 2 { lh.append(r + 12) }
        return Array(Set(lh + rh)).filter { $0 >= 24 && $0 < melody }.sorted()
    }

    /// Remember the voicing that was actually played so the next suggestions lead smoothly from it.
    public func didPlay(voicing: [Int], chord: Chord) {
        lastVoicing = voicing
        commit(chord: chord)
    }

    // MARK: Helpers

    func adjust(_ c: Chord) -> Chord {
        switch complexity {
        case .genre: return c
        case .simple: return Chord(root: c.root, quality: Self.simplify(c.quality))
        case .rich: return Chord(root: c.root, quality: Self.enrich(c.quality))
        }
    }

    static func simplify(_ q: ChordQuality) -> ChordQuality {
        switch q.family {
        case .major: return q == .augmented ? .augmented : .major
        case .dominant: return .major
        case .minor: return .minor
        case .diminished: return .diminished
        case .suspended: return q
        case .power: return .power
        }
    }

    static func enrich(_ q: ChordQuality) -> ChordQuality {
        switch q {
        case .major: return .major7
        case .minor: return .minor7
        case .diminished: return .halfDiminished7
        case .dominant7: return .dominant9
        case .major7: return .major9
        case .minor7: return .minor9
        case .sus4: return .dominant7sus4
        default: return q
        }
    }

    func diatonicChords(key: Key, scale: ScaleType) -> [Chord] {
        let ivs = scale.intervals
        guard ivs.count == 7 else {
            // Pentatonic / blues: fall back to the parent major or minor scale.
            return diatonicChords(key: key, scale: key.isMinor ? .naturalMinor : .major)
        }
        var result: [Chord] = []
        for d in 0..<7 {
            let r = ivs[d]
            let third = mod12(ivs[(d + 2) % 7] - r)
            let fifth = mod12(ivs[(d + 4) % 7] - r)
            let seventh = mod12(ivs[(d + 6) % 7] - r)
            var q: ChordQuality
            switch (third, fifth) {
            case (4, 7): q = .major
            case (3, 7): q = .minor
            case (3, 6): q = .diminished
            case (4, 8): q = .augmented
            default: continue
            }
            if complexity == .rich {
                switch (q, seventh) {
                case (.major, 11): q = .major7
                case (.major, 10): q = .dominant7
                case (.minor, 10): q = .minor7
                case (.minor, 11): q = .minorMajor7
                case (.diminished, 10): q = .halfDiminished7
                case (.diminished, 9): q = .diminished7
                default: break
                }
            }
            result.append(Chord(root: key.tonic + r, quality: q))
        }
        return result
    }

    /// Suggests next melody notes: stepwise motion in the scale from the highest held note,
    /// plus the tones of the next suggested chord near that note.
    func melodyHints(held: [Int], key: Key, scalePCs: Set<Int>, scaleType: ScaleType, next: Chord?) -> [Int] {
        guard let top = held.max() else { return [] }
        var notes = Set<Int>()
        // Up to two scale steps up and down.
        var up = top, down = top, foundUp = 0, foundDown = 0
        while foundUp < 2 && up < top + 7 {
            up += 1
            if scalePCs.contains(mod12(up)) { notes.insert(up); foundUp += 1 }
        }
        while foundDown < 2 && down > top - 7 {
            down -= 1
            if scalePCs.contains(mod12(down)) { notes.insert(down); foundDown += 1 }
        }
        if let n = next {
            for pc in n.pitchClasses {
                // nearest occurrence above the top note within an octave
                var m = top - 5
                while mod12(m) != pc { m += 1 }
                if m != top { notes.insert(m) }
            }
        }
        // Genre colour notes within a fifth.
        for off in genre.signatureNotes {
            let pc = mod12(key.tonic + off)
            for m in (top - 6)...(top + 6) where mod12(m) == pc && m != top { notes.insert(m) }
        }
        return notes.filter { !held.contains($0) }.sorted()
    }
}
