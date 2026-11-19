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
