import Foundation

// MARK: - Pitch classes

public enum NoteName {
    public static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    public static let flats  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    public static let italian = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]

    public static func name(_ pitchClass: Int, flats useFlats: Bool = false) -> String {
        let pc = mod12(pitchClass)
        return useFlats ? flats[pc] : sharps[pc]
    }

    /// "C4" style name for a MIDI note (middle C = 60 = C4).
    public static func midiName(_ note: Int) -> String {
        return name(note) + String(note / 12 - 1)
    }
}

@inline(__always) public func mod12(_ v: Int) -> Int { ((v % 12) + 12) % 12 }

// MARK: - Chord quality

public enum ChordQuality: String, CaseIterable, Codable, Hashable {
    case major, minor, diminished, augmented, sus2, sus4, power
    case six, minor6
    case dominant7, major7, minor7, halfDiminished7, diminished7, minorMajor7, dominant7sus4
    case add9, minorAdd9, major9, minor9, dominant9, dominant7sharp9, minor11, dominant13

    /// Intervals in semitones from the root.
    public var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .diminished: return [0, 3, 6]
        case .augmented: return [0, 4, 8]
        case .sus2: return [0, 2, 7]
        case .sus4: return [0, 5, 7]
        case .power: return [0, 7]
        case .six: return [0, 4, 7, 9]
        case .minor6: return [0, 3, 7, 9]
        case .dominant7: return [0, 4, 7, 10]
        case .major7: return [0, 4, 7, 11]
        case .minor7: return [0, 3, 7, 10]
        case .halfDiminished7: return [0, 3, 6, 10]
        case .diminished7: return [0, 3, 6, 9]
        case .minorMajor7: return [0, 3, 7, 11]
        case .dominant7sus4: return [0, 5, 7, 10]
        case .add9: return [0, 4, 7, 14]
        case .minorAdd9: return [0, 3, 7, 14]
        case .major9: return [0, 4, 7, 11, 14]
        case .minor9: return [0, 3, 7, 10, 14]
        case .dominant9: return [0, 4, 7, 10, 14]
        case .dominant7sharp9: return [0, 4, 7, 10, 15]
        case .minor11: return [0, 3, 7, 10, 14, 17]
        case .dominant13: return [0, 4, 7, 10, 14, 21]
        }
    }

    public var symbol: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .augmented: return "aug"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        case .power: return "5"
        case .six: return "6"
        case .minor6: return "m6"
        case .dominant7: return "7"
        case .major7: return "maj7"
        case .minor7: return "m7"
        case .halfDiminished7: return "m7b5"
        case .diminished7: return "dim7"
        case .minorMajor7: return "m(maj7)"
        case .dominant7sus4: return "7sus4"
        case .add9: return "add9"
        case .minorAdd9: return "m(add9)"
        case .major9: return "maj9"
        case .minor9: return "m9"
        case .dominant9: return "9"
        case .dominant7sharp9: return "7#9"
        case .minor11: return "m11"
        case .dominant13: return "13"
        }
    }

    /// Basic triad "family" used to compare chords loosely (Cmaj7 ≈ C).
    public var family: ChordFamily {
        switch self {
        case .major, .six, .major7, .add9, .major9, .augmented: return .major
        case .dominant7, .dominant9, .dominant7sharp9, .dominant13, .dominant7sus4: return .dominant
        case .minor, .minor6, .minor7, .minorMajor7, .minorAdd9, .minor9, .minor11: return .minor
        case .diminished, .halfDiminished7, .diminished7: return .diminished
        case .sus2, .sus4: return .suspended
        case .power: return .power
        }
    }

    /// Simpler qualities are preferred by the detector when several fit equally well.
    var complexity: Int { intervals.count }
}

public enum ChordFamily: Hashable {
    case major, dominant, minor, diminished, suspended, power

    /// Whether two families are "close enough" to count as the same harmonic function.
    public func matches(_ other: ChordFamily) -> Bool {
        if self == other { return true }
        let pair: Set<ChordFamily> = [self, other]
        // A plain major triad and a dominant 7th share the same function often enough.
        if pair == [.major, .dominant] { return true }
        // Power chords and sus chords are ambiguous: they fit major or minor.
        if self == .power || other == .power { return other != .diminished && self != .diminished }
        if pair.contains(.suspended) && (pair.contains(.major) || pair.contains(.dominant)) { return true }
        return false
    }
}

// MARK: - Chord

public struct Chord: Hashable, Codable, CustomStringConvertible {
    public var root: Int          // pitch class 0...11
    public var quality: ChordQuality
    public var bass: Int?         // slash-chord bass pitch class

    public init(root: Int, quality: ChordQuality, bass: Int? = nil) {
        self.root = mod12(root)
        self.quality = quality
        if let b = bass, mod12(b) != mod12(root) { self.bass = mod12(b) } else { self.bass = nil }
    }

    public var pitchClasses: Set<Int> { Set(quality.intervals.map { mod12(root + $0) }) }

    public func name(flats: Bool = false) -> String {
        var s = NoteName.name(root, flats: flats) + quality.symbol
        if let b = bass { s += "/" + NoteName.name(b, flats: flats) }
        return s
    }

    public var description: String { name() }

    public func transposed(by semitones: Int) -> Chord {
        Chord(root: root + semitones, quality: quality, bass: bass.map { $0 + semitones })
    }

    /// Loose equality: same root and compatible family (ignores extensions and inversions).
    public func isLooselyEqual(_ other: Chord) -> Bool {
        root == other.root && quality.family.matches(other.quality.family)
    }

    /// Builds a playable voicing (MIDI notes) close to `center`, choosing the inversion that
    /// moves the least from `previous` if given (smooth voice-leading).
    public func voicing(near center: Int, previous: [Int] = [], withBass: Bool = true) -> [Int] {
        let ints = quality.intervals.map { $0 > 12 ? $0 - 12 : $0 }
        let uniquePCs = Array(Set(ints.map { mod12(root + $0) }))
        var best: [Int] = []
        var bestCost = Int.max
        // Try every inversion in two octaves around the center.
        for inversion in 0..<max(1, ints.count) {
            for octaveShift in [-12, 0, 12] {
                var notes: [Int] = []
                let base = ((center - 6) / 12) * 12 + octaveShift
                let ordered = Array(ints[inversion...] + ints[..<inversion])
                var last = Int.min
                for iv in ordered {
                    var n = base + mod12(root + iv)
                    while n <= last { n += 12 }
                    notes.append(n)
                    last = n
                }
                guard let lo = notes.first, let hi = notes.last, lo >= 24, hi <= 108 else { continue }
                let mid = (lo + hi) / 2
                var cost = abs(mid - center) * 2
                if !previous.isEmpty {
                    cost = 0
                    for n in notes { cost += previous.map { abs($0 - n) }.min() ?? 0 }
                    cost += abs(mid - center) / 2
                }
                if cost < bestCost { bestCost = cost; best = notes }
            }
        }
        if best.isEmpty { best = uniquePCs.map { center + $0 }.sorted() }
        if withBass, let lowest = best.first {
            var b = (lowest / 12) * 12 + (bass ?? root)
            while b >= lowest - 4 { b -= 12 }
            if b >= 24 { best.insert(b, at: 0) }
        }
        return best
    }
}

// MARK: - Chord detection

public enum ChordDetector {
    /// Detects the most likely chord from a set of MIDI notes. Needs at least 2 distinct pitch classes.
    public static func detect(_ midiNotes: [Int]) -> Chord? {
        guard let lowest = midiNotes.min() else { return nil }
        let pcs = Set(midiNotes.map(mod12))
        guard pcs.count >= 2 else { return nil }
        let bassPC = mod12(lowest)

        var best: (chord: Chord, score: Double)?
        for root in 0..<12 {
            for q in ChordQuality.allCases {
                let tones = Set(q.intervals.map { mod12(root + $0) })
                let hit = pcs.intersection(tones).count
                let extra = pcs.subtracting(tones).count
                let missing = tones.subtracting(pcs).count
                // Every played note should be explained; root should be present.
                guard extra == 0 else { continue }
                var score = Double(hit) * 2.0 - Double(missing) * 1.6
                if !pcs.contains(root) { score -= 2.5 }
                if root == bassPC { score += 1.2 }
                // Is the fifth (if any) missing? small penalty only.
                score -= Double(q.complexity) * 0.05
                if q == .power && pcs.count > 2 { score -= 5 }
                if score > (best?.score ?? -Double.infinity) {
                    best = (Chord(root: root, quality: q, bass: bassPC), score)
                }
            }
        }
        guard let found = best, found.score > 0 else { return nil }
        return found.chord
    }
}

// MARK: - Scales & keys

public enum ScaleType: String, CaseIterable, Codable {
    case major, naturalMinor, harmonicMinor, melodicMinor
    case dorian, phrygian, lydian, mixolydian, locrian
    case majorPentatonic, minorPentatonic, blues, phrygianDominant

    public var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: return [0, 2, 3, 5, 7, 9, 11]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .locrian: return [0, 1, 3, 5, 6, 8, 10]
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .blues: return [0, 3, 5, 6, 7, 10]
        case .phrygianDominant: return [0, 1, 4, 5, 7, 8, 10]
        }
    }

    public var isMinor: Bool { intervals.contains(3) && !intervals.contains(4) }

    public var displayName: String {
        switch self {
        case .major: return "Maggiore"
        case .naturalMinor: return "Minore naturale"
        case .harmonicMinor: return "Minore armonica"
        case .melodicMinor: return "Minore melodica"
        case .dorian: return "Dorica"
        case .phrygian: return "Frigia"
        case .lydian: return "Lidia"
        case .mixolydian: return "Misolidia"
        case .locrian: return "Locria"
        case .majorPentatonic: return "Pentatonica maggiore"
        case .minorPentatonic: return "Pentatonica minore"
        case .blues: return "Blues"
        case .phrygianDominant: return "Frigia dominante"
        }
    }
}

public struct Key: Hashable, Codable, CustomStringConvertible {
    public var tonic: Int
    public var isMinor: Bool

    public init(tonic: Int, isMinor: Bool) {
        self.tonic = mod12(tonic)
        self.isMinor = isMinor
    }

    public var description: String { NoteName.name(tonic, flats: prefersFlats) + (isMinor ? " minore" : " maggiore") }
    public var shortName: String { NoteName.name(tonic, flats: prefersFlats) + (isMinor ? "m" : "") }

    /// Keys like F, Bb, Eb, Dm, Gm... are normally written with flats.
    public var prefersFlats: Bool {
        let majorTonic = isMinor ? mod12(tonic + 3) : tonic
        return [5, 10, 3, 8, 1, 6].contains(majorTonic)
    }

    public func scale(_ type: ScaleType) -> Set<Int> { Set(type.intervals.map { mod12(tonic + $0) }) }
}

// MARK: - Key detection (Krumhansl–Schmuckler)

public enum KeyDetector {
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// `histogram` = weight of each pitch class (e.g. note durations or counts).
    /// `minorBias` > 0 favours minor keys (useful for genres that are mostly minor).
    public static func detect(histogram: [Double], minorBias: Double = 0) -> Key? {
        guard histogram.count == 12, histogram.reduce(0, +) > 0 else { return nil }
        var best: (Key, Double)?
        for tonic in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                let rotated = (0..<12).map { profile[mod12($0 - tonic)] }
                var r = correlation(histogram, rotated)
                if minor { r += minorBias }
                if r > (best?.1 ?? -.infinity) { best = (Key(tonic: tonic, isMinor: minor), r) }
            }
        }
        return best?.0
    }

    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / Double(a.count)
        let mb = b.reduce(0, +) / Double(b.count)
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<a.count {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        let den = (da * db).squareRoot()
        return den == 0 ? 0 : num / den
    }
}
