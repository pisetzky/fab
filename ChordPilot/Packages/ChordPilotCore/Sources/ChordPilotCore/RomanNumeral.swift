import Foundation

/// A chord expressed relative to a key, e.g. "bVII", "ii7", "V7#9", "i", "Imaj9".
public struct RomanChord: Hashable, Codable, CustomStringConvertible {
    public var offset: Int            // semitones above the key tonic
    public var quality: ChordQuality
    public var symbol: String         // original text, for display

    public var description: String { symbol }

    public func chord(in key: Key) -> Chord {
        Chord(root: key.tonic + offset, quality: quality)
    }

    /// Parses a roman numeral. Uppercase numerals are major, lowercase minor.
    /// Supported suffixes: 7 maj7 9 maj9 6 add9 sus2 sus4 5 dim o ° o7 ø7 m7b5 + 7#9 11 13 7sus4
    public static func parse(_ text: String) -> RomanChord? {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        var accidental = 0
        while let c = s.first, c == "b" || c == "#" {
            accidental += (c == "b") ? -1 : 1
            s = s.dropFirst()
        }
        let numeralChars = s.prefix { "IViv".contains($0) }
        guard !numeralChars.isEmpty else { return nil }
        let numeral = String(numeralChars)
        let suffix = String(s.dropFirst(numeralChars.count))
        let degreeTable = ["I": 0, "II": 2, "III": 4, "IV": 5, "V": 7, "VI": 9, "VII": 11]
        guard let base = degreeTable[numeral.uppercased()] else { return nil }
        let isUpper = numeral == numeral.uppercased()

        let quality: ChordQuality
        switch suffix {
        case "": quality = isUpper ? .major : .minor
        case "7": quality = isUpper ? .dominant7 : .minor7
        case "maj7": quality = isUpper ? .major7 : .minorMajor7
        case "9": quality = isUpper ? .dominant9 : .minor9
        case "maj9": quality = .major9
        case "6": quality = isUpper ? .six : .minor6
        case "add9": quality = isUpper ? .add9 : .minorAdd9
        case "sus2": quality = .sus2
        case "sus4": quality = .sus4
        case "7sus4": quality = .dominant7sus4
        case "5": quality = .power
        case "dim", "o", "°": quality = .diminished
        case "o7", "°7", "dim7": quality = .diminished7
        case "ø7", "ø", "m7b5": quality = .halfDiminished7
        case "+", "aug": quality = .augmented
        case "7#9": quality = .dominant7sharp9
        case "11": quality = .minor11
        case "13": quality = .dominant13
        default: return nil
        }
        return RomanChord(offset: mod12(base + accidental), quality: quality, symbol: text)
    }

    /// Labels a chord relative to a key, e.g. G7 in C major → "V7".
    public static func label(for chord: Chord, in key: Key) -> String {
        let offset = mod12(chord.root - key.tonic)
        let names: [Int: String] = [0: "I", 2: "II", 4: "III", 5: "IV", 7: "V", 9: "VI", 11: "VII"]
        let flatNames: [Int: String] = [1: "bII", 3: "bIII", 6: "bV", 8: "bVI", 10: "bVII"]
        var numeral = names[offset] ?? flatNames[offset] ?? "?"
        // Minor keys conventionally name degrees from the minor scale.
        if key.isMinor {
            let minorNames: [Int: String] = [3: "III", 8: "VI", 10: "VII", 4: "#III", 9: "#VI", 11: "#VII"]
            numeral = minorNames[offset] ?? numeral
        }
        let family = chord.quality.family
        let lower = family == .minor || family == .diminished
        if lower {
            // keep accidental prefix, lowercase the numeral
            let prefix = numeral.prefix { $0 == "b" || $0 == "#" }
            numeral = String(prefix) + numeral.dropFirst(prefix.count).lowercased()
        }
        var suffix: String
        switch chord.quality {
        case .major, .minor: suffix = ""
        case .diminished: suffix = "°"
        case .halfDiminished7: suffix = "ø7"
        case .diminished7: suffix = "°7"
        case .augmented: suffix = "+"
        case .minor7: suffix = "7"
        case .minor6: suffix = "6"
        case .minor9: suffix = "9"
        case .minorAdd9: suffix = "add9"
        case .minorMajor7: suffix = "maj7"
        default: suffix = chord.quality.symbol
        }
        return numeral + suffix
    }
}

public extension Array where Element == RomanChord {
    /// Parses "I V vi IV" style strings.
    static func progression(_ text: String) -> [RomanChord] {
        text.split(separator: " ").compactMap { RomanChord.parse(String($0)) }
    }
}
