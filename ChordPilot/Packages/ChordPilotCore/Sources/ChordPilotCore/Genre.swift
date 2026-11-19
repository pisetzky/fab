import Foundation

/// A weighted chord progression typical of a genre.
public struct GenreProgression: Hashable {
    public var chords: [RomanChord]
    public var weight: Double

    public init(_ text: String, weight: Double = 1) {
        self.chords = .progression(text)
        self.weight = weight
    }
}

/// Everything ChordPilot knows about how a genre "sounds": its scales, progressions,
/// characteristic notes and the rhythm used by the genre player.
public struct Genre: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var emoji: String
    public var prefersMinor: Bool
    public var defaultTonic: Int
    public var bpm: Double
    public var majorScale: ScaleType
    public var minorScale: ScaleType
    public var progressions: [GenreProgression]
    /// Colour notes (semitones above tonic) that give the genre its flavour, highlighted as melody hints.
    public var signatureNotes: [Int]
    /// 16 steps per bar. x = accent hit, o = soft hit, a = arpeggio note, - = hold, . = release
    public var chordRhythm: String
    /// 16 steps per bar. x = root, f = fifth, o = root octave up, - = hold, . = release
    public var bassRhythm: String
    public var barsPerChord: Int
    /// Hex RGB colour used in the UI for this genre's glow.
    public var colorHex: UInt32
    public var octave: Int  // centre MIDI note for voicings

    public var defaultKey: Key { Key(tonic: defaultTonic, isMinor: prefersMinor) }

    public func scale(for key: Key) -> ScaleType { key.isMinor ? minorScale : majorScale }

    /// The key in which this genre's progressions should be read. Progressions are written for the
    /// genre's preferred mode, so a major key is converted to its relative minor (same notes) and vice versa.
    public func progressionKey(for key: Key) -> Key {
        if prefersMinor == key.isMinor { return key }
        return prefersMinor ? Key(tonic: key.tonic + 9, isMinor: true) : Key(tonic: key.tonic + 3, isMinor: false)
    }

    public static func == (lhs: Genre, rhs: Genre) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension Genre {
    /// The 23 genres offered in the drop-down menu.
    static let all: [Genre] = [
        Genre(id: "pop", name: "Pop", emoji: "🎤", prefersMinor: false, defaultTonic: 0, bpm: 110,
              majorScale: .major, minorScale: .naturalMinor,
              progressions: [.init("I V vi IV", weight: 3), .init("vi IV I V", weight: 2),
                             .init("I vi IV V", weight: 1.5), .init("IV I V vi"), .init("I IV vi V"),
                             .init("I iii IV V", weight: 0.7)],
              signatureNotes: [2, 9], chordRhythm: "x---o---x---o---", bassRhythm: "x.......x...x...",
              barsPerChord: 1, colorHex: 0xFF4FD8, octave: 60),

        Genre(id: "rock", name: "Rock", emoji: "🎸", prefersMinor: false, defaultTonic: 9, bpm: 120,
              majorScale: .mixolydian, minorScale: .minorPentatonic,
              progressions: [.init("I bVII IV I", weight: 2.5), .init("I IV V IV", weight: 2),
                             .init("I V IV", weight: 1.5), .init("vi IV I V"), .init("I bIII IV I"),
                             .init("I5 bVII5 IV5", weight: 1.2)],
              signatureNotes: [10, 3], chordRhythm: "x-o-x-o-x-o-x-o-", bassRhythm: "x-x-x-x-x-x-x-x-",
              barsPerChord: 1, colorHex: 0xFF5A36, octave: 57),

        Genre(id: "hiphop", name: "Hip-Hop", emoji: "🎧", prefersMinor: true, defaultTonic: 2, bpm: 90,
              majorScale: .major, minorScale: .naturalMinor,
              progressions: [.init("i bVI bIII bVII", weight: 2), .init("i iv bVI V", weight: 1.5),
                             .init("i7 iv7", weight: 2), .init("i bVII bVI V"), .init("i7 bVImaj7 bIII bVII")],
              signatureNotes: [3, 10, 8], chordRhythm: "x-------.---o---", bassRhythm: "x.....x...x.....",
              barsPerChord: 1, colorHex: 0xFFC233, octave: 60),

        Genre(id: "trap", name: "Trap", emoji: "🔥", prefersMinor: true, defaultTonic: 5, bpm: 140,
              majorScale: .major, minorScale: .harmonicMinor,
              progressions: [.init("i bVI iv V", weight: 2), .init("i bII", weight: 1.5),
                             .init("i iv bVI V", weight: 1.5), .init("i bVI bVII i"), .init("i v bVI V")],
              signatureNotes: [1, 11, 8], chordRhythm: "x---------------", bassRhythm: "x.......x..x....",
              barsPerChord: 1, colorHex: 0xB44DFF, octave: 60),

        Genre(id: "rnb", name: "R&B", emoji: "💜", prefersMinor: false, defaultTonic: 3, bpm: 85,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("Imaj7 vi7 ii7 V7", weight: 2), .init("ii9 V13 Imaj9", weight: 2),
                             .init("IVmaj7 iii7 vi7", weight: 1.5), .init("Imaj7 IVmaj7", weight: 1.5),
                             .init("IVmaj7 V7sus4 iii7 vi9")],
              signatureNotes: [2, 9, 11], chordRhythm: "x-----o-----o---", bassRhythm: "x.....x.....x...",
              barsPerChord: 1, colorHex: 0x9D6BFF, octave: 60),

        Genre(id: "jazz", name: "Jazz", emoji: "🎷", prefersMinor: false, defaultTonic: 10, bpm: 120,
              majorScale: .major, minorScale: .melodicMinor,
              progressions: [.init("ii7 V7 Imaj7", weight: 3), .init("Imaj7 vi7 ii7 V7", weight: 2),
                             .init("iii7 VI7 ii7 V7", weight: 1.5), .init("ii7 bII7 Imaj7", weight: 1.2),
                             .init("Imaj7 I7 IVmaj7 iv7", weight: 1), .init("iiø7 V7#9 i7")],
              signatureNotes: [2, 9, 11, 6], chordRhythm: "..x..x.....x..x.", bassRhythm: "x...f...x...f...",
              barsPerChord: 1, colorHex: 0x33C4FF, octave: 60),

        Genre(id: "blues", name: "Blues", emoji: "🎺", prefersMinor: false, defaultTonic: 9, bpm: 95,
              majorScale: .blues, minorScale: .blues,
              progressions: [.init("I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7", weight: 3),
                             .init("I7 IV7 I7 V7", weight: 1.5), .init("I7 IV7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 I7")],
              signatureNotes: [3, 6, 10], chordRhythm: "x--ox--ox--ox--o", bassRhythm: "x..fx..fx..fx..f",
              barsPerChord: 1, colorHex: 0x3D7BFF, octave: 57),

        Genre(id: "edm", name: "EDM", emoji: "⚡️", prefersMinor: true, defaultTonic: 9, bpm: 128,
              majorScale: .major, minorScale: .naturalMinor,
              progressions: [.init("i bVI bIII bVII", weight: 3), .init("i bVII bVI bVII", weight: 1.5),
                             .init("bVI bVII i", weight: 1.5), .init("i bIII bVII bVI")],
              signatureNotes: [2, 7], chordRhythm: "x-------x-------", bassRhythm: "..x...x...x...x.",
              barsPerChord: 1, colorHex: 0x00F0FF, octave: 60),

        Genre(id: "house", name: "House", emoji: "🏠", prefersMinor: true, defaultTonic: 7, bpm: 124,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("i9 iv9", weight: 2.5), .init("i7 bVIImaj7 bVImaj7 bVII", weight: 1.5),
                             .init("ii7 V7 Imaj7"), .init("i7 IV7", weight: 1.5)],
              signatureNotes: [9, 2], chordRhythm: "..x...x...x...x.", bassRhythm: "..x...x...x...x.",
              barsPerChord: 1, colorHex: 0x2DFFA8, octave: 60),

        Genre(id: "techno", name: "Techno", emoji: "🔊", prefersMinor: true, defaultTonic: 9, bpm: 130,
              majorScale: .mixolydian, minorScale: .phrygian,
              progressions: [.init("i bII", weight: 2), .init("i bVII", weight: 2), .init("i iv", weight: 1.5),
                             .init("i5 bVI5", weight: 1.2)],
              signatureNotes: [1, 7], chordRhythm: "x..x..x...x..x..", bassRhythm: "..xx..xx..xx..xx",
              barsPerChord: 2, colorHex: 0x19D3C5, octave: 57),

        Genre(id: "melodictechno", name: "Melodic Techno", emoji: "🌌", prefersMinor: true, defaultTonic: 2, bpm: 124,
              majorScale: .lydian, minorScale: .naturalMinor,
              progressions: [.init("i bVI bIII bVII", weight: 3), .init("i bVII bVI bVII", weight: 2),
                             .init("iadd9 bVImaj7 bIIImaj7 bVII", weight: 2), .init("i v bVI iv", weight: 1.5)],
              signatureNotes: [2, 7], chordRhythm: "aaaaaaaaaaaaaaaa", bassRhythm: "..x...x...x...x.",
              barsPerChord: 2, colorHex: 0x8E6CFF, octave: 60),

        Genre(id: "afrohouse", name: "Melodic Afro House", emoji: "🥁", prefersMinor: true, defaultTonic: 9, bpm: 122,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("i bVII bVI bVII", weight: 2.5), .init("i iv bVII bIII", weight: 2),
                             .init("i7 iv7 bVIImaj7", weight: 1.5), .init("i bVI bVII", weight: 1.5)],
              signatureNotes: [9, 2], chordRhythm: "..x..x..x..x.x..", bassRhythm: "x..x...x..x.....",
              barsPerChord: 1, colorHex: 0x3DFFB0, octave: 60),

        Genre(id: "reggaeton", name: "Reggaeton", emoji: "🌴", prefersMinor: true, defaultTonic: 4, bpm: 95,
              majorScale: .major, minorScale: .naturalMinor,
              progressions: [.init("i bVI bIII bVII", weight: 2.5), .init("i bVII bVI V", weight: 1.5),
                             .init("i iv bVII bIII"), .init("i bVI bVII")],
              signatureNotes: [3, 7], chordRhythm: "x..x..x.x..x..x.", bassRhythm: "x..x..x.x..x..x.",
              barsPerChord: 1, colorHex: 0xFF8A00, octave: 60),

        Genre(id: "latin", name: "Latin / Bossa", emoji: "💃", prefersMinor: false, defaultTonic: 5, bpm: 130,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("Imaj7 II7 ii7 V7", weight: 2), .init("ii7 V7 Imaj7 VI7", weight: 2),
                             .init("Imaj7 bIIIo7 ii7 V7"), .init("i7 iv7 V7 i7", weight: 1)],
              signatureNotes: [2, 9, 11], chordRhythm: "x..x..x...x..x..", bassRhythm: "x..fx..fx..fx..f",
              barsPerChord: 1, colorHex: 0xFFD23F, octave: 60),

        Genre(id: "country", name: "Country", emoji: "🤠", prefersMinor: false, defaultTonic: 7, bpm: 110,
              majorScale: .majorPentatonic, minorScale: .naturalMinor,
              progressions: [.init("I IV V I", weight: 3), .init("I V vi IV", weight: 1.5),
                             .init("I IV I V", weight: 1.5), .init("I I7 IV iv")],
              signatureNotes: [2, 9, 3], chordRhythm: "x.o.x.o.x.o.x.o.", bassRhythm: "x...f...x...f...",
              barsPerChord: 1, colorHex: 0xE0A060, octave: 60),

        Genre(id: "funk", name: "Funk", emoji: "🕺", prefersMinor: true, defaultTonic: 4, bpm: 105,
              majorScale: .mixolydian, minorScale: .dorian,
              progressions: [.init("i9 IV9", weight: 3), .init("i7 iv7 i7 V7#9", weight: 1.5),
                             .init("I7#9 IV9"), .init("i7 bVII7 i7 IV7")],
              signatureNotes: [9, 10, 3], chordRhythm: "x..x..x.x.x..x..", bassRhythm: "x..x.x..x.xx..x.",
              barsPerChord: 1, colorHex: 0xFF3D8B, octave: 60),

        Genre(id: "gospel", name: "Gospel / Soul", emoji: "🙌", prefersMinor: false, defaultTonic: 8, bpm: 80,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("Imaj7 iii7 vi7 ii7 V7", weight: 2), .init("IV V iii vi ii V I", weight: 2),
                             .init("IVmaj7 #ivø7 I V7"), .init("I I7 IV iv", weight: 1.5),
                             .init("ii7 V7sus4 V7 Imaj9")],
              signatureNotes: [2, 9, 10], chordRhythm: "x-----x---x-----", bassRhythm: "x.....x...x.....",
              barsPerChord: 1, colorHex: 0xFFB000, octave: 60),

        Genre(id: "metal", name: "Metal", emoji: "🤘", prefersMinor: true, defaultTonic: 4, bpm: 140,
              majorScale: .mixolydian, minorScale: .phrygian,
              progressions: [.init("i5 bVI5 bVII5 i5", weight: 2.5), .init("i5 bII5 i5 bVII5", weight: 2),
                             .init("i bVI bIII bVII"), .init("i5 iv5 bVI5 V5")],
              signatureNotes: [1, 6], chordRhythm: "x.x.x.x.x.x.x.x.", bassRhythm: "x.x.x.x.x.x.x.x.",
              barsPerChord: 1, colorHex: 0xD0D0D0, octave: 52),

        Genre(id: "reggae", name: "Reggae", emoji: "🇯🇲", prefersMinor: false, defaultTonic: 7, bpm: 75,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("I IV", weight: 3), .init("I V vi IV", weight: 1.5),
                             .init("I IV V IV", weight: 1.5), .init("ii V")],
              signatureNotes: [2, 9], chordRhythm: "..x...x...x...x.", bassRhythm: "x.....x.x.......",
              barsPerChord: 1, colorHex: 0x3BD16F, octave: 60),

        Genre(id: "classical", name: "Classica", emoji: "🎻", prefersMinor: false, defaultTonic: 0, bpm: 100,
              majorScale: .major, minorScale: .harmonicMinor,
              progressions: [.init("I IV V I", weight: 2.5), .init("I vi ii V I", weight: 2),
                             .init("I IV viio iii vi ii V I", weight: 1.5), .init("I V vi iii IV I IV V", weight: 1.5),
                             .init("i iv V i")],
              signatureNotes: [11, 2], chordRhythm: "aaaaaaaaaaaaaaaa", bassRhythm: "x-------x-------",
              barsPerChord: 1, colorHex: 0xF5E6C8, octave: 60),

        Genre(id: "lofi", name: "Lo-Fi", emoji: "☕️", prefersMinor: false, defaultTonic: 5, bpm: 80,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("ii9 V9 Imaj9", weight: 2.5), .init("IVmaj7 iii7 ii7 Imaj7", weight: 2),
                             .init("Imaj7 vi9 ii9 V7sus4", weight: 1.5), .init("IVmaj7 iii7 vi7 V7")],
              signatureNotes: [2, 9, 11], chordRhythm: "x-------..x-----", bassRhythm: "x.......x.......",
              barsPerChord: 1, colorHex: 0xC9A7FF, octave: 60),

        Genre(id: "afrobeats", name: "Afrobeats", emoji: "🌍", prefersMinor: false, defaultTonic: 1, bpm: 105,
              majorScale: .major, minorScale: .dorian,
              progressions: [.init("vi IV I V", weight: 2), .init("ii V I", weight: 1.5),
                             .init("I vi ii V", weight: 1.5), .init("IV V vi", weight: 1.5), .init("ii7 iii7 IVmaj7")],
              signatureNotes: [2, 9], chordRhythm: "x..x..x...x..x..", bassRhythm: "x..x...xx.......",
              barsPerChord: 1, colorHex: 0x5CFF4F, octave: 60),

        Genre(id: "cinematic", name: "Cinematic", emoji: "🎬", prefersMinor: true, defaultTonic: 2, bpm: 80,
              majorScale: .lydian, minorScale: .naturalMinor,
              progressions: [.init("i bVI bIII bVII", weight: 2), .init("i bVI iv V", weight: 2),
                             .init("bVI bVII i", weight: 1.5), .init("i bIII bVII IV"), .init("I II IV I", weight: 0.8)],
              signatureNotes: [2, 7], chordRhythm: "x---------------", bassRhythm: "x---------------",
              barsPerChord: 2, colorHex: 0x7FA8FF, octave: 60)
    ]

    static func byID(_ id: String) -> Genre { all.first { $0.id == id } ?? all[0] }
}
