import Foundation

/// A note event in the genre player loop, expressed in 16th-note steps.
public struct PatternEvent: Equatable {
    public var step: Int
    public var note: UInt8
    public var velocity: UInt8   // 0 = note off
}

public struct GenrePattern {
    public var events: [PatternEvent]   // sorted by step, offs before ons on the same step
    public var totalSteps: Int
    public var chords: [Chord]
    public var bpm: Double
}

/// Turns a genre progression + rhythm into a loop of MIDI events the audio engine can play.
public enum GenrePatternBuilder {
    public static func build(genre: Genre, key: Key, progressionIndex: Int = 0,
                             complexity: ChordComplexity = .genre) -> GenrePattern {
        let pKey = genre.progressionKey(for: key)
        let prog = genre.progressions[max(0, min(progressionIndex, genre.progressions.count - 1))]
        let engine = SuggestionEngine(genre: genre)
        engine.complexity = complexity
        let chords = prog.chords.map { engine.adjust($0.chord(in: pKey)) }

        let chordSteps = Array(genre.chordRhythm)
        let bassSteps = Array(genre.bassRhythm)
        let stepsPerChord = 16 * max(1, genre.barsPerChord)
        let total = stepsPerChord * chords.count
        var events: [PatternEvent] = []

        var previousVoicing: [Int] = []
        for (ci, chord) in chords.enumerated() {
            let voicing = chord.voicing(near: genre.octave, previous: previousVoicing, withBass: false)
            previousVoicing = voicing
            let arpOrder = arpeggioOrder(count: voicing.count)
            var bassRoot = (voicing.first ?? 48) / 12 * 12 + chord.root
            // Keep the whole bass lane (root, fifth, octave) strictly below the chord voicing.
            while bassRoot + 12 >= (voicing.first ?? 48) { bassRoot -= 12 }
            if bassRoot < 24 { bassRoot += 12 }
            let fifthOffset = chord.quality.intervals.contains(7) ? 7 :
                (chord.quality.intervals.contains(6) ? 6 : (chord.quality.intervals.contains(8) ? 8 : 7))

            var chordOn: [Int] = []
            var bassOn: Int?
            var arpIndex = 0
            for s in 0..<stepsPerChord {
                let step = ci * stepsPerChord + s
                let c = chordSteps[s % 16]
                let b = bassSteps[s % 16]

                // Chord lane
                switch c {
                case "x", "o":
                    for n in chordOn { events.append(PatternEvent(step: step, note: UInt8(n), velocity: 0)) }
                    let vel: UInt8 = c == "x" ? 104 : 78
                    chordOn = voicing
                    for n in voicing { events.append(PatternEvent(step: step, note: UInt8(n), velocity: vel)) }
                case "a":
                    for n in chordOn { events.append(PatternEvent(step: step, note: UInt8(n), velocity: 0)) }
                    let n = voicing[arpOrder[arpIndex % arpOrder.count]]
                    arpIndex += 1
                    chordOn = [n]
                    events.append(PatternEvent(step: step, note: UInt8(n), velocity: arpIndex % 4 == 1 ? 92 : 72))
                case ".":
                    for n in chordOn { events.append(PatternEvent(step: step, note: UInt8(n), velocity: 0)) }
                    chordOn = []
                default: break  // "-" hold
                }

                // Bass lane
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
            // Release everything at the chord change.
            let end = (ci + 1) * stepsPerChord
            let endStep = end == total ? 0 : end
            for n in chordOn { events.append(PatternEvent(step: endStep, note: UInt8(n), velocity: 0)) }
            if let n = bassOn { events.append(PatternEvent(step: endStep, note: UInt8(n), velocity: 0)) }
        }

        // Sort: by step, note-offs first so re-triggered notes are not cut.
        events.sort { $0.step == $1.step ? ($0.velocity == 0 && $1.velocity != 0) : $0.step < $1.step }
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
