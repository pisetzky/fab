import XCTest
@testable import ChordPilotCore

final class ChordPilotCoreTests: XCTestCase {

    func testTwentyGenres() {
        XCTAssertEqual(Genre.all.count, 20)
        XCTAssertEqual(Set(Genre.all.map { $0.id }).count, 20)
    }

    func testAllProgressionsParse() {
        for g in Genre.all {
            XCTAssertEqual(g.chordRhythm.count, 16, g.name)
            XCTAssertEqual(g.bassRhythm.count, 16, g.name)
            XCTAssertFalse(g.progressions.isEmpty, g.name)
            for p in g.progressions {
                XCTAssertFalse(p.chords.isEmpty, g.name)
            }
        }
        // Token count must equal parsed count for every progression string.
        let samples = ["I V vi IV", "ii7 V7 Imaj7", "iiø7 V7#9 i7", "I IV viio iii vi ii V I", "IVmaj7 #ivø7 I V7",
                       "Imaj7 bIIIo7 ii7 V7", "i5 bII5 i5 bVII5", "ii9 V13 Imaj9", "Imaj7 vi9 ii9 V7sus4"]
        for s in samples {
            XCTAssertEqual([RomanChord].progression(s).count, s.split(separator: " ").count, s)
        }
    }

    func testRomanParsing() {
        let c = Key(tonic: 0, isMinor: false)
        XCTAssertEqual(RomanChord.parse("V7")!.chord(in: c), Chord(root: 7, quality: .dominant7))
        XCTAssertEqual(RomanChord.parse("bVII")!.chord(in: c), Chord(root: 10, quality: .major))
        XCTAssertEqual(RomanChord.parse("ii7")!.chord(in: c), Chord(root: 2, quality: .minor7))
        XCTAssertEqual(RomanChord.parse("viio")!.chord(in: c), Chord(root: 11, quality: .diminished))
    }

    func testChordDetection() {
        XCTAssertEqual(ChordDetector.detect([60, 64, 67])?.name(), "C")
        XCTAssertEqual(ChordDetector.detect([57, 60, 64])?.name(), "Am")
        XCTAssertEqual(ChordDetector.detect([55, 59, 62, 65])?.name(), "G7")
        XCTAssertEqual(ChordDetector.detect([64, 67, 72])?.name(), "C/E")
        XCTAssertEqual(ChordDetector.detect([62, 65, 69, 72])?.name(), "Dm7")
        XCTAssertNil(ChordDetector.detect([60]))
    }

    func testKeyDetection() {
        var h = [Double](repeating: 0, count: 12)
        for pc in [0, 2, 4, 5, 7, 9, 11, 0, 4, 7, 0] { h[pc] += 1 }
        XCTAssertEqual(KeyDetector.detect(histogram: h), Key(tonic: 0, isMinor: false))
    }

    func testPopSuggestsAfterC() {
        let engine = SuggestionEngine(genre: Genre.byID("pop"))
        engine.fixedKey = Key(tonic: 0, isMinor: false)
        let r = engine.suggest(held: [60, 64, 67])
        XCTAssertEqual(r.currentChordName, "C")
        XCTAssertFalse(r.chords.isEmpty)
        // I → V is the most common pop move.
        XCTAssertEqual(r.chords.first?.chord.name(), "G")
        XCTAssertFalse(r.chords.contains { $0.chord.name() == "C" })
        // The best chord's tones are highlighted as primary.
        for n in r.chords[0].voicing { XCTAssertEqual(r.highlights[n]?.role, .primary) }
    }

    func testJazzIIVI() {
        let engine = SuggestionEngine(genre: Genre.byID("jazz"))
        engine.fixedKey = Key(tonic: 0, isMinor: false)
        let r = engine.suggest(held: [50, 53, 57, 60]) // Dm7
        XCTAssertEqual(r.chords.first?.chord, Chord(root: 7, quality: .dominant7))
    }

    func testMinorGenreInMajorKeyUsesRelativeMinor() {
        let g = Genre.byID("hiphop")
        XCTAssertEqual(g.progressionKey(for: Key(tonic: 0, isMinor: false)), Key(tonic: 9, isMinor: true))
    }

    func testSingleNoteHarmonised() {
        let engine = SuggestionEngine(genre: Genre.byID("pop"))
        engine.fixedKey = Key(tonic: 0, isMinor: false)
        let r = engine.suggest(held: [64]) // E
        XCTAssertTrue(r.chords.first!.chord.pitchClasses.contains(4))
        XCTAssertFalse(r.melodyNotes.isEmpty)
    }

    func testEveryGenreProducesSuggestionsAndPattern() {
        for g in Genre.all {
            let engine = SuggestionEngine(genre: g)
            for cx in ChordComplexity.allCases {
                engine.complexity = cx
                let r = engine.suggest(held: [57, 60, 64])
                XCTAssertGreaterThanOrEqual(r.chords.count, 3, g.name)
                let p = GenrePatternBuilder.build(genre: g, key: g.defaultKey, complexity: cx)
                XCTAssertGreaterThan(p.events.count, 0, g.name)
                XCTAssertTrue(p.events.allSatisfy { $0.step >= 0 && $0.step < p.totalSteps }, g.name)
                XCTAssertTrue(p.events.allSatisfy { $0.note >= 21 && $0.note <= 108 }, g.name)
                // Every note-on must eventually be turned off (balanced loop).
                var balance = [Int](repeating: 0, count: 128)
                for e in p.events { balance[Int(e.note)] += e.velocity > 0 ? 1 : -1 }
                XCTAssertTrue(balance.allSatisfy { $0 == 0 }, "\(g.name) unbalanced pattern")
            }
        }
    }

    func testVoicingIsSmooth() {
        let c = Chord(root: 0, quality: .major).voicing(near: 60, withBass: false)
        let f = Chord(root: 5, quality: .major).voicing(near: 60, previous: c, withBass: false)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(f.count, 3)
        // C → F with smooth voice-leading: total movement ≤ 3 semitones.
        let moved = zip(c, f).map { abs($0 - $1) }.reduce(0, +)
        XCTAssertLessThanOrEqual(moved, 3)
    }
}
