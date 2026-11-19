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
    @Published public private(set) var piano: PianoModel = PianoModel.all[0]
    @Published public private(set) var arpeggio = -1
    @Published public private(set) var melody = -1
    @Published public private(set) var song = 0
    @Published public private(set) var genius = false
    @Published public private(set) var melodyNotes: Set<Int> = []
    /// Pianist mode: gold keys = suggested next notes → chord name.
    @Published public private(set) var geniusNext: [Int: String] = [:]
    @Published public private(set) var twoHands = false
    @Published public private(set) var notesOnly = false
    /// Easy mode: only the essentials on screen, Genius mode always on. On at first launch.
    @Published public var easyMode: Bool = UserDefaults.standard.object(forKey: "cp.easy") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(easyMode, forKey: "cp.easy")
            if easyMode && !genius { setGenius(true) }
        }
    }
    private var lastGeniusVersion = -1
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
        arpeggio = au.arpeggio; melody = au.melody; song = au.song; genius = au.genius
        twoHands = au.parameterValue(.hands) > 0.5; notesOnly = au.parameterValue(.notesOnly) > 0.5
        if easyMode && !genius { au.set(.genius, 1) }
        piano = PianoModel.all[max(0, min(PianoModel.all.count - 1, Int(au.parameterValue(.piano).rounded())))]
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
        var p = Set<Int>(), mel = Set<Int>()
        for n in 0..<128 {
            if k.heldNotes[n] > 0 { h.insert(n) }
            if k.patternNotes[n] > 0 { p.insert(n) }
            if k.melodyNotes[n] > 0 { mel.insert(n) }
        }
        if p != patternNotes { patternNotes = p }
        if mel != melodyNotes { melodyNotes = mel }
        let idx = Int(k.patternChordIndex)
        if idx != patternChordIndex { patternChordIndex = idx }

        checkInspirationEnd()
        if genius, au.geniusVersion != lastGeniusVersion {
            lastGeniusVersion = au.geniusVersion
            var g: [Int: String] = [:]
            for s in au.geniusSuggestions() { g[s.note] = chordName(s.chord) }
            if g != geniusNext { geniusNext = g }
        } else if !genius && !geniusNext.isEmpty { geniusNext = [:] }
        if h != held {
            recordInspiration(added: h.subtracting(held), removed: held.subtracting(h))
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
        // Channel 16 marks tapped suggestions (not counted as held, never transformed by Genius mode).
        for n in notes { k.sendFromUI(status: 0x9F, data1: UInt8(n), data2: 96) }
        engine.didPlay(voicing: s.voicing, chord: s.chord)
        lastCommitted = s.chord
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            for n in notes { self?.audioUnit?.kernel.sendFromUI(status: 0x8F, data1: UInt8(n), data2: 0) }
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
    public func setArpeggio(_ i: Int) { audioUnit?.set(.arpeggio, AUValue(i + 1)) }
    public func setMelody(_ i: Int) { audioUnit?.set(.melody, AUValue(i + 1)) }
    public func setGenius(_ on: Bool) { audioUnit?.set(.genius, on ? 1 : 0) }
    public func newSong() { audioUnit?.newSong() }
    public func setTwoHands(_ on: Bool) { audioUnit?.set(.hands, on ? 1 : 0) }
    public func setNotesOnly(_ on: Bool) { audioUnit?.set(.notesOnly, on ? 1 : 0) }

    // MARK: Inspiration

    @Published public private(set) var inspireStatus = "Premi Registra e suona (o fai partire la traccia nella DAW): parte dalla prima nota."
    @Published public private(set) var inspireOptions: [InspirationOption] = []
    @Published public private(set) var inspireRecording = false
    private var inspireStart: Date?
    private var inspireTotal = 64
    private var inspireOpen: [Int: (step: Int, vel: Int)] = [:]
    private var inspireNotes: [RecordedNote] = []
    private var inspireSource: [RecordedNote] = []
    private var inspireChords: [Chord] = []

    public func startInspiration(bars: Int) {
        inspireTotal = bars * 16; inspireStart = nil; inspireOpen = [:]; inspireNotes = []; inspireRecording = true
        inspireStatus = "⏺ In attesa della prima nota (\(bars) battute a \(Int(bpm)) BPM)…"
    }

    public func inspirationFromPlayer() {
        guard let p = audioUnit?.currentPattern else { return }
        var rec: [RecordedNote] = []
        var open: [Int: PatternEvent] = [:]
        for e in p.events {
            let k = Int(e.lane) * 1000 + Int(e.note)
            if e.velocity > 0 { open[k] = e }
            else if let o = open.removeValue(forKey: k) {
                rec.append(RecordedNote(step: o.step, note: Int(o.note), velocity: Int(o.velocity), length: max(1, (e.step == 0 ? p.totalSteps : e.step) - o.step)))
            }
        }
        inspireTotal = p.totalSteps
        analyseInspiration(rec)
    }

    private func inspirationStep() -> Int {
        guard let t0 = inspireStart else { return 0 }
        return Int((Date().timeIntervalSince(t0) / (60.0 / max(20, bpm) / 4.0)).rounded())
    }

    private func recordInspiration(added: Set<Int>, removed: Set<Int>) {
        guard inspireRecording, let k = audioUnit?.kernel else { return }
        if inspireStart == nil { guard !added.isEmpty else { return }; inspireStart = Date() }
        let step = inspirationStep()
        for n in removed { if let o = inspireOpen.removeValue(forKey: n) { inspireNotes.append(RecordedNote(step: o.step, note: n, velocity: o.vel, length: max(1, min(step, inspireTotal) - o.step))) } }
        if step < inspireTotal { for n in added { inspireOpen[n] = (step, Int(k.heldNotes[n])) } }
    }

    private func checkInspirationEnd() {
        guard inspireRecording, inspireStart != nil else { return }
        let step = inspirationStep()
        inspireStatus = "⏺ Battuta \(min(inspireTotal / 16, step / 16 + 1)) di \(inspireTotal / 16)…"
        guard step >= inspireTotal else { return }
        inspireRecording = false
        for (n, o) in inspireOpen { inspireNotes.append(RecordedNote(step: o.step, note: n, velocity: o.vel, length: max(1, inspireTotal - o.step))) }
        inspireOpen = [:]
        if inspireNotes.isEmpty { inspireStatus = "Nessuna nota registrata: riprova." } else { analyseInspiration(inspireNotes) }
    }

    private func analyseInspiration(_ rec: [RecordedNote]) {
        inspireSource = rec
        let r = Inspiration.suggest(genre: genre, recorded: rec, totalSteps: inspireTotal, fixedKey: engine.fixedKey)
        inspireChords = r.chords
        inspireOptions = r.options
        inspireStatus = "Traccia in \(noteName(r.key.tonic, flats: r.key.prefersFlats))\(r.key.isMinor ? " minore" : " maggiore") · accordi "
            + r.chords.map { chordName($0) }.joined(separator: " – ")
    }

    private func inspirationPattern(_ i: Int) -> GenrePattern? {
        guard i < inspireOptions.count else { return nil }
        var ev: [PatternEvent] = []
        for n in inspireSource {
            let end = n.step + n.length
            ev.append(PatternEvent(step: n.step, note: UInt8(n.note), velocity: UInt8(max(1, n.velocity)), lane: 0))
            ev.append(PatternEvent(step: end >= inspireTotal ? 0 : end, note: UInt8(n.note), velocity: 0, lane: 0))
        }
        ev += inspireOptions[i].events
        ev = ev.enumerated().sorted { a, b in
            if a.element.step != b.element.step { return a.element.step < b.element.step }
            let ao = a.element.velocity == 0, bo = b.element.velocity == 0
            return ao != bo ? ao : a.offset < b.offset
        }.map { $0.element }
        return GenrePattern(events: ev, totalSteps: inspireTotal, chords: inspireChords, bpm: bpm)
    }

    public func playInspiration(_ i: Int) { if let p = inspirationPattern(i) { audioUnit?.playCustom(p) } }

    public func exportInspiration(_ i: Int) -> URL? {
        guard let p = inspirationPattern(i) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChordPilot-ispirazione-\(i + 1).mid")
        do { try MidiExport.data(pattern: p, bpm: bpm, loops: 4).write(to: url); return url } catch { return nil }
    }

    // Pro options
    public func proValue(_ a: ParamAddress) -> Double { Double(audioUnit?.parameterValue(a) ?? 0) }
    public func setPro(_ a: ParamAddress, _ v: Double) { audioUnit?.set(a, AUValue(v)); objectWillChange.send() }

    /// Writes the current genre-player song (4 loops) as a MIDI file and returns its URL for sharing.
    public func exportMIDI() -> URL? {
        guard let au = audioUnit, let p = au.currentPattern else { return nil }
        let data = MidiExport.data(pattern: p, bpm: Double(au.parameterValue(.bpm)), loops: 4)
        let name = "ChordPilot-\(genre.id)\(arpeggio >= 0 ? "-arp\(arpeggio + 1)" : "")\(melody >= 0 ? "-mel\(melody + 1)" : "").mid"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
    }
    public func setPiano(_ m: PianoModel) { audioUnit?.set(.piano, AUValue(PianoModel.all.firstIndex(of: m) ?? 0)) }
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
