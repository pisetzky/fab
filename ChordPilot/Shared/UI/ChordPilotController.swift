import Foundation
import SwiftUI
import Combine
import ChordPilotCore

/// Bridges the Audio Unit (real-time engine) and the SwiftUI interface.
/// Polls the engine ~30 times per second and turns what is held into suggestions.
@MainActor
public final class ChordPilotController: ObservableObject {

    @Published public private(set) var result: SuggestionResult
    @Published public private(set) var held: Set<Int> = []
    @Published public private(set) var patternNotes: Set<Int> = []
    @Published public private(set) var patternChordIndex = 0
    @Published public private(set) var patternChords: [Chord] = []

    @Published public private(set) var genre: Genre = Genre.all[0]
    @Published public private(set) var keySelection = 0          // 0 = Auto, 1...12 = C...B
    @Published public private(set) var minorMode = false
    @Published public private(set) var complexity: ChordComplexity = .genre
    @Published public private(set) var isPlaying = false
    @Published public private(set) var bpm: Double = 110
    @Published public private(set) var synthOn = true
    @Published public private(set) var hostSync = true
    @Published public private(set) var progressionIndex = 0
    @Published public var italianNames = Locale.current.language.languageCode?.identifier == "it"
    @Published public var lowestNote = 48        // C3
    @Published public var octaves = 3
    @Published public var showScaleHints = true
    @Published public var connectionStatus: String = ""

    public let engine = SuggestionEngine()
    public private(set) var audioUnit: ChordPilotAudioUnit?
    private var timer: Timer?
    private var lastHeldKey: [Int] = []
    private var lastCommitted: Chord?
    private var chordStableSince: Date?

    public var isMIDIEffect: Bool { audioUnit?.isMIDIEffect ?? false }

    public init() {
        result = .empty(Genre.all[0].defaultKey)
        recompute()
    }

    // MARK: Connection

    public func attach(_ au: ChordPilotAudioUnit) {
        audioUnit = au
        au.onStateChange = { [weak self] in
            Task { @MainActor in self?.syncFromAudioUnit() }
        }
        syncFromAudioUnit()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func detach() {
        timer?.invalidate()
        timer = nil
        audioUnit?.onStateChange = nil
    }

    private func syncFromAudioUnit() {
        guard let au = audioUnit else { return }
        genre = au.genre
        keySelection = Int(au.parameterValue(.keyRoot).rounded())
        minorMode = au.parameterValue(.keyMinor) > 0.5
        complexity = au.complexity
        isPlaying = au.parameterValue(.play) > 0.5
        bpm = Double(au.parameterValue(.bpm))
        synthOn = au.parameterValue(.synth) > 0.5
        hostSync = au.parameterValue(.hostSync) > 0.5
        progressionIndex = au.progressionIndex
        patternChords = au.currentPattern?.chords ?? []
        engine.genre = genre
        engine.complexity = complexity
        engine.fixedKey = keySelection == 0 ? nil : Key(tonic: keySelection - 1, isMinor: minorMode)
        recompute()
    }

    // MARK: Polling the audio engine

    private func poll() {
        guard let au = audioUnit else { return }
        let k = au.kernel
        // New note-ons feed the automatic key detection.
        var msg: UInt32 = 0
        while cp_ring_pop(k.lastNotesRing, &msg) {
            engine.registerNoteOn(Int(msg & 0x7F), velocity: Int((msg >> 8) & 0x7F))
        }
        var h = Set<Int>()
        var p = Set<Int>()
        for n in 0..<128 {
            if k.heldNotes[n] > 0 { h.insert(n) }
            if k.patternNotes[n] > 0 { p.insert(n) }
        }
        if p != patternNotes { patternNotes = p }
        let idx = Int(k.patternChordIndex)
        if idx != patternChordIndex { patternChordIndex = idx }

        if h != held {
            held = h
            chordStableSince = Date()
            recompute()
        } else if let since = chordStableSince, Date().timeIntervalSince(since) > 0.25 {
            // Once a chord has been held for a moment it becomes part of the musical context.
            chordStableSince = nil
            if let c = result.currentChord, lastCommitted.map({ !$0.isLooselyEqual(c) }) ?? true {
                engine.commit(chord: c)
                lastCommitted = c
                recompute()
            }
        }
        if keySelection == 0 {
            let detected = engine.currentKey
            if au.detectedKey != detected { au.detectedKey = detected }
        }
    }

    private func recompute() {
        engine.lowNote = lowestNote
        engine.highNote = lowestNote + octaves * 12
        let r = engine.suggest(held: Array(held))
        if r != result { result = r }
    }

    // MARK: Keyboard input

    public func noteDown(_ note: Int, velocity: Int) {
        guard let k = audioUnit?.kernel else { return }
        k.sendFromUI(status: 0x90, data1: UInt8(note), data2: UInt8(max(1, min(127, velocity))))
    }

    public func noteUp(_ note: Int) {
        audioUnit?.kernel.sendFromUI(status: 0x80, data1: UInt8(note), data2: 0)
    }

    /// Plays a suggested chord (and sends it to the MIDI output so the DAW can record it).
    public func play(_ s: ChordSuggestion) {
        guard let k = audioUnit?.kernel else { return }
        var notes = s.voicing
        if let low = notes.first {
            var bass = (low / 12) * 12 + s.chord.root
            while bass >= low { bass -= 12 }
            if bass >= 24 { notes.insert(bass, at: 0) }
        }
        for n in notes { k.sendFromUI(status: 0x90, data1: UInt8(n), data2: 96) }
        engine.didPlay(voicing: s.voicing, chord: s.chord)
        lastCommitted = s.chord
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            for n in notes { self?.audioUnit?.kernel.sendFromUI(status: 0x80, data1: UInt8(n), data2: 0) }
            self?.recompute()
        }
        recompute()
    }

    // MARK: Settings (written through the AU parameters so the DAW sees and saves them)

    public func setGenre(_ g: Genre) {
        audioUnit?.set(.genre, AUValue(Genre.all.firstIndex(of: g) ?? 0))
        if audioUnit == nil { genre = g; engine.genre = g; recompute() }
        engine.reset()
        lastCommitted = nil
    }
    public func setKey(_ selection: Int) { audioUnit?.set(.keyRoot, AUValue(selection)) }
    public func setMinor(_ m: Bool) { audioUnit?.set(.keyMinor, m ? 1 : 0) }
    public func setComplexity(_ c: ChordComplexity) { audioUnit?.set(.complexity, AUValue(c.rawValue)) }
    public func togglePlay() { audioUnit?.set(.play, isPlaying ? 0 : 1) }
    public func setBPM(_ v: Double) { audioUnit?.set(.bpm, AUValue(max(40, min(220, v)))) }
    public func setSynth(_ on: Bool) { audioUnit?.set(.synth, on ? 1 : 0) }
    public func setHostSync(_ on: Bool) { audioUnit?.set(.hostSync, on ? 1 : 0) }
    public func setProgression(_ i: Int) { audioUnit?.set(.progression, AUValue(i)) }
    public func resetContext() { engine.reset(); lastCommitted = nil; recompute() }

    public func shiftOctave(_ delta: Int) {
        lowestNote = max(24, min(84, lowestNote + delta * 12))
        recompute()
    }
    public func setOctaves(_ n: Int) {
        octaves = max(1, min(6, n))
        recompute()
    }

    public func noteName(_ pc: Int, flats: Bool) -> String {
        italianNames ? NoteName.italian[mod12(pc)] : NoteName.name(pc, flats: flats)
    }

    public func chordName(_ c: Chord) -> String {
        let flats = result.key.prefersFlats
        if !italianNames { return c.name(flats: flats) }
        var s = NoteName.italian[c.root] + c.quality.symbol
        if let b = c.bass { s += "/" + NoteName.italian[b] }
        return s
    }
}
