import AVFoundation
import AudioToolbox
import CoreAudioKit
import ChordPilotCore

/// Component descriptions for the two flavours of the plug-in.
/// - Instrument (aumu): plays its own piano and sends MIDI out → loads as an instrument in every AUv3 host.
/// - MIDI FX (aumi): passes your MIDI through and adds the genre player → for Logic Pro, AUM, Cubasis, Loopy Pro...
public enum ChordPilotComponent {
    public static let manufacturer: FourCharCode = fourCC("FabA")
    public static let instrument = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice, componentSubType: fourCC("chpl"),
        componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    public static let midiEffect = AudioComponentDescription(
        componentType: kAudioUnitType_MIDIProcessor, componentSubType: fourCC("chpm"),
        componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)

    static func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}

public final class ChordPilotAudioUnit: AUAudioUnit {

    let kernel = ChordPilotDSPKernel()
    private var outputBus: AUAudioUnitBus!
    private var _outputBusses: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!
    private var renderBuffer: AVAudioPCMBuffer?
    private var _currentPreset: AUAudioUnitPreset?

    // MARK: Musical state (main thread)
    public private(set) var genre: Genre = Genre.all[0]
    /// nil = automatic key detection.
    public private(set) var fixedKey: Key?
    public var detectedKey: Key? {
        didSet { if fixedKey == nil && detectedKey != oldValue { schedulePatternRebuild() } }
    }
    public private(set) var complexity: ChordComplexity = .genre
    public private(set) var progressionIndex = 0
    public private(set) var arpeggio = -1        // -1 = genre rhythm
    public private(set) var melody = -1          // -1 = no melody
    public private(set) var song = 0             // song variation seed
    public private(set) var genius = false
    private let geniusEngine = SuggestionEngine()
    private var geniusTimer: Timer?
    public private(set) var currentPattern: GenrePattern?

    /// Called on the main thread whenever a parameter changes (host automation, preset, UI).
    public var onStateChange: (() -> Void)?

    public var isMIDIEffect: Bool { componentDescription.componentType == kAudioUnitType_MIDIProcessor }
    public var playerKey: Key { fixedKey ?? detectedKey ?? genre.defaultKey }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.maximumChannelCount = 2
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        kernel.isMIDIEffect = componentDescription.componentType == kAudioUnitType_MIDIProcessor
        maximumFramesToRender = 4096
        setupParameters()   // also schedules the first genre-player pattern
    }

    // MARK: - Busses & capabilities

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }
    public override var channelCapabilities: [NSNumber]? { [0, 2, 0, 1] }
    public override var midiOutputNames: [String] { ["ChordPilot MIDI Out"] }
    public override var canProcessInPlace: Bool { true }
    public override var supportsUserPresets: Bool { true }
    public override var audioUnitShortName: String? { "ChordPilot" }

    public override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* fixed tree */ }
    }

    // MARK: - Parameters

    private func setupParameters() {
        let genreNames = Genre.all.map { "\($0.emoji) \($0.name)" }
        let keyNames = ["Auto"] + NoteName.sharps
        func p(_ id: String, _ name: String, _ addr: ParamAddress, _ min: AUValue, _ max: AUValue,
               _ unit: AudioUnitParameterUnit, _ values: [String]? = nil) -> AUParameter {
            AUParameterTree.createParameter(withIdentifier: id, name: name, address: addr.rawValue,
                                            min: min, max: max, unit: unit, unitName: nil,
                                            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
                                            valueStrings: values, dependentParameters: nil)
        }
        let params = [
            p("genre", "Genere", .genre, 0, AUValue(Genre.all.count - 1), .indexed, genreNames),
            p("key", "Tonalità", .keyRoot, 0, 12, .indexed, keyNames),
            p("minor", "Modo minore", .keyMinor, 0, 1, .boolean),
            p("complexity", "Complessità", .complexity, 0, 2, .indexed, ChordComplexity.allCases.map { $0.displayName }),
            p("volume", "Volume", .volume, 0, 1, .linearGain),
            p("synth", "Pianoforte interno", .synth, 0, 1, .boolean),
            p("sync", "Sync DAW", .hostSync, 0, 1, .boolean),
            p("play", "Genre Player", .play, 0, 1, .boolean),
            p("progression", "Progressione", .progression, 0, 5, .indexed, (1...6).map { "Progressione \($0)" }),
            p("bpm", "BPM", .bpm, 40, 220, .BPM),
            p("piano", "Pianoforte", .piano, 0, AUValue(PianoModel.all.count - 1), .indexed,
              PianoModel.all.map { "\($0.emoji) \($0.name)" }),
            p("arpeggio", "Arpeggio", .arpeggio, 0, AUValue(Arpeggios.all.count), .indexed,
              ["Ritmo del genere"] + Arpeggios.all.enumerated().map { "\($0.offset + 1). \($0.element.name)" }),
            p("melody", "Melodia", .melody, 0, AUValue(Melodies.count), .indexed,
              ["Nessuna"] + Melodies.names.enumerated().map { "\($0.offset + 1). \($0.element)" }),
            p("song", "Canzone", .song, 0, 9999, .generic),
            p("genius", "Modalità Genio", .genius, 0, 1, .boolean),
            // Pro options (all off by default)
            p("onefinger", "Accordi con un dito", .oneFinger, 0, 1, .boolean),
            p("scalelock", "Blocca scala", .scaleLock, 0, 1, .boolean),
            p("strum", "Strum (ms)", .strum, 0, 120, .milliseconds),
            p("humanize", "Humanize (%)", .humanize, 0, 100, .percent),
            p("swing", "Swing (%)", .swing, 0, 60, .percent),
            p("transpose", "Trasponi", .transpose, -12, 12, .relativeSemiTones),
            p("drums", "Batteria", .drums, 0, 1, .boolean),
            p("hands", "Due mani", .hands, 0, 1, .boolean),
            p("split", "Divisione mani", .split, 36, 84, .midiNoteNumber),
            p("notesonly", "Solo note (Genio)", .notesOnly, 0, 1, .boolean),
            p("voicing", "Voicing", .voicing, 0, AUValue(SuggestionEngine.voicingStyles.count - 1), .indexed, SuggestionEngine.voicingStyles)
        ]
        params[Int(ParamAddress.volume.rawValue)].value = 0.8
        params[Int(ParamAddress.synth.rawValue)].value = kernel.isMIDIEffect ? 0 : 1
        params[Int(ParamAddress.hostSync.rawValue)].value = 1
        params[Int(ParamAddress.bpm.rawValue)].value = AUValue(genre.bpm)
        params.first { $0.address == ParamAddress.transpose.rawValue }?.value = 0
        _parameterTree = AUParameterTree.createTree(withChildren: params)

        _parameterTree.implementorValueObserver = { [weak self] param, value in
            self?.apply(address: param.address, value: value)
        }
        _parameterTree.implementorValueProvider = { [weak self] param in
            self?.value(for: param.address) ?? param.value
        }
        _parameterTree.implementorStringFromValueCallback = { param, valuePtr in
            let v = valuePtr?.pointee ?? param.value
            if let strings = param.valueStrings, !strings.isEmpty {
                return strings[max(0, min(strings.count - 1, Int(v.rounded())))]
            }
            if param.unit == .boolean { return v > 0.5 ? "On" : "Off" }
            return String(format: "%.2f", v)
        }
        for param in params { apply(address: param.address, value: param.value) }
    }

    private func value(for address: AUParameterAddress) -> AUValue {
        switch ParamAddress(rawValue: address) {
        case .genre: return AUValue(Genre.all.firstIndex(of: genre) ?? 0)
        case .keyRoot: return fixedKey.map { AUValue($0.tonic + 1) } ?? 0
        case .keyMinor: return (fixedKey?.isMinor ?? false) ? 1 : 0
        case .complexity: return AUValue(complexity.rawValue)
        case .volume: return kernel.volume
        case .synth: return kernel.synthEnabled ? 1 : 0
        case .hostSync: return kernel.hostSync ? 1 : 0
        case .play: return cp_atomic_load(kernel.playRequest) != 0 ? 1 : 0
        case .progression: return AUValue(progressionIndex)
        case .bpm: return AUValue(kernel.internalBPM)
        case .piano: return AUValue(kernel.pianoType)
        case .arpeggio: return AUValue(arpeggio + 1)
        case .melody: return AUValue(melody + 1)
        case .song: return AUValue(song)
        case .genius: return genius ? 1 : 0
        case .oneFinger: return kernel.oneFingerEnabled ? 1 : 0
        case .scaleLock: return kernel.scaleLockEnabled ? 1 : 0
        case .strum: return AUValue(kernel.strumMs)
        case .humanize: return AUValue(kernel.humanize * 100)
        case .swing: return AUValue(kernel.swing * 100)
        case .transpose: return AUValue(kernel.transpose)
        case .voicing: return AUValue(kernel.voicingStyle)
        case .drums: return kernel.drumsEnabled ? 1 : 0
        case .hands: return kernel.twoHandsEnabled ? 1 : 0
        case .split: return AUValue(kernel.splitNote)
        case .notesOnly: return kernel.notesOnly ? 1 : 0
        case .none: return 0
        }
    }

    private var minorFlag = false

    private func apply(address: AUParameterAddress, value: AUValue) {
        var rebuild = false
        switch ParamAddress(rawValue: address) {
        case .genre:
            let g = Genre.all[max(0, min(Genre.all.count - 1, Int(value.rounded())))]
            if g != genre {
                genre = g
                progressionIndex = 0
                kernel.internalBPM = g.bpm
                rebuild = true
            }
        case .keyRoot:
            let idx = Int(value.rounded())
            fixedKey = idx == 0 ? nil : Key(tonic: idx - 1, isMinor: minorFlag)
            rebuild = true
        case .keyMinor:
            minorFlag = value > 0.5
            if let k = fixedKey { fixedKey = Key(tonic: k.tonic, isMinor: minorFlag) }
            rebuild = true
        case .complexity:
            complexity = ChordComplexity(rawValue: Int(value.rounded())) ?? .genre
            rebuild = true
        case .volume: kernel.volume = value
        case .synth: kernel.synthEnabled = value > 0.5
        case .hostSync: kernel.hostSync = value > 0.5
        case .play: cp_atomic_store(kernel.playRequest, value > 0.5 ? 1 : 0)
        case .progression:
            progressionIndex = max(0, min(genre.progressions.count - 1, Int(value.rounded())))
            rebuild = true
        case .bpm: kernel.internalBPM = Double(value)
        case .piano: kernel.pianoType = max(0, min(PianoModel.all.count - 1, Int(value.rounded())))
        case .arpeggio: arpeggio = max(-1, min(Arpeggios.all.count - 1, Int(value.rounded()) - 1)); rebuild = true
        case .melody: melody = max(-1, min(Melodies.count - 1, Int(value.rounded()) - 1)); rebuild = true
        case .song: song = max(0, Int(value.rounded())); rebuild = true
        case .genius:
            genius = value > 0.5
            kernel.geniusEnabled = genius
            scheduleGeniusRefresh()
        case .oneFinger: kernel.oneFingerEnabled = value > 0.5; scheduleGeniusRefresh()
        case .scaleLock: kernel.scaleLockEnabled = value > 0.5; scheduleGeniusRefresh()
        case .strum: kernel.strumMs = Double(max(0, min(120, value)))
        case .humanize: kernel.humanize = Double(max(0, min(100, value))) / 100
        case .swing: kernel.swing = Double(max(0, min(60, value))) / 100
        case .transpose: kernel.transpose = Int(value.rounded())
        case .voicing: kernel.voicingStyle = Int(value.rounded())
        case .drums: kernel.drumsEnabled = value > 0.5
        case .hands: kernel.twoHandsEnabled = value > 0.5; scheduleGeniusRefresh()
        case .split: kernel.splitNote = max(36, min(84, Int(value.rounded())))
        case .notesOnly: kernel.notesOnly = value > 0.5
        case .none: break
        }
        if rebuild { schedulePatternRebuild() } else { notifyStateChange() }
    }

    private var rebuildScheduled = false
    private func schedulePatternRebuild() {
        if Thread.isMainThread && !rebuildScheduled {
            rebuildPattern()
            return
        }
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.rebuildScheduled = false
            self?.rebuildPattern()
        }
    }

    private func writeDrums() {
        let d = genre.drums
        for (k, lane) in [d.kick, d.snare, d.hat].enumerated() {
            let chars = Array(lane)
            for s in 0..<16 { kernel.drumLanes[k * 16 + s] = s < chars.count && chars[s] == "x" ? 1 : 0 }
        }
    }

    private func rebuildPattern() {
        writeDrums()
        let p = GenrePatternBuilder.build(genre: genre, key: playerKey, progressionIndex: progressionIndex,
                                          complexity: complexity, arpeggio: arpeggio, melody: melody, seed: song)
        currentPattern = p
        scheduleGeniusRefresh()
        kernel.publishPattern(events: p.events.map { ($0.step, $0.note, $0.velocity, $0.lane) },
                              totalSteps: p.totalSteps, stepsPerChord: 16 * max(1, genre.barsPerChord))
        notifyStateChange()
    }

    /// Plays a ready-made loop (e.g. a track + an Inspiration melody) until a musical setting changes.
    public func playCustom(_ p: GenrePattern) {
        currentPattern = p
        kernel.publishPattern(events: p.events.map { ($0.step, $0.note, $0.velocity, $0.lane) },
                              totalSteps: p.totalSteps, stepsPerChord: 16)
        set(.play, 1)
        notifyStateChange()
    }

    /// A completely different song: new progression, arpeggio, melody and variation – and start playing.
    public func newSong() {
        set(.progression, AUValue(Int.random(in: 0..<genre.progressions.count)))
        set(.arpeggio, AUValue(Int.random(in: 1...Arpeggios.all.count)))
        set(.melody, AUValue(Int.random(in: 1...Melodies.count)))
        set(.song, AUValue(Int.random(in: 1...9999)))
        set(.play, 1)
    }

    // MARK: Genius mode (main thread): learns from what is played and refreshes the kernel's lookup table.

    private func scheduleGeniusRefresh() {
        let work = { [weak self] in
            guard let self else { return }
            let needsTable = self.genius || self.kernel.oneFingerEnabled || self.kernel.scaleLockEnabled || self.kernel.twoHandsEnabled
            if needsTable && self.geniusTimer == nil {
                let t = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.geniusTick() }
                RunLoop.main.add(t, forMode: .common)
                self.geniusTimer = t
            } else if !needsTable {
                self.geniusTimer?.invalidate(); self.geniusTimer = nil
            }
            self.refreshGeniusTable()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func geniusTick() {
        var msg: UInt32 = 0, changed = false
        while cp_ring_pop(kernel.geniusRing, &msg) {
            changed = true
            if msg & 0x10000 != 0 { geniusEngine.registerNoteOn(Int(msg & 0x7F)); geniusEngine.geniusPlayed(Int(msg & 0x7F)) }
            else if msg & 0x20000 != 0 {
                let q = ChordQuality.allCases[min(ChordQuality.allCases.count - 1, Int(msg & 0xFF))]
                geniusEngine.commit(chord: Chord(root: Int((msg >> 8) & 0xFF), quality: q))
            }
        }
        if changed { refreshGeniusTable() }
    }

    /// Bumps whenever the musical context of Genius mode changes (the UI then refreshes its suggestions).
    public private(set) var geniusVersion = 0
    /// Pianist mode: the suggested next melody notes, each with the chord it will produce.
    public func geniusSuggestions() -> [(note: Int, chord: Chord)] { geniusEngine.geniusNext() }

    private func refreshGeniusTable() {
        if geniusEngine.genre != genre { geniusEngine.genre = genre; geniusEngine.reset() }
        geniusEngine.complexity = complexity
        geniusEngine.fixedKey = fixedKey ?? (genius ? nil : detectedKey)
        let entries: [(shift: Int, root: Int, quality: Int, tones: [Int])] = (0..<12).map { pc in
            let g = geniusEngine.genius(note: 60 + pc)
            var tones: [Int] = []
            for iv in g.chord.quality.intervals where !tones.contains(mod12(g.chord.root + iv)) { tones.append(mod12(g.chord.root + iv)) }
            return (g.shift, g.chord.root, ChordQuality.allCases.firstIndex(of: g.chord.quality) ?? 0, tones)
        }
        let of = geniusEngine.oneFingerTable().map { (root: $0.root, tones: $0.tones) }
        let locks = (0..<12).map { geniusEngine.lockToScale(60 + $0) - (60 + $0) }
        let ofChords = geniusEngine.oneFingerTable()
        let hands: [(ofThird: Int, ofUpper: Int, leftRoot: Int, leftThird: Int, leftUpper: Int, leftQuality: Int)] = (0..<12).map { pc in
            func shell(_ q: ChordQuality) -> (Int, Int) {
                let iv = q.intervals.map { $0 % 12 }
                return (iv[1], iv.count > 3 && iv[3] > iv[1] ? iv[3] : iv[2])
            }
            let o = shell(ofChords[pc].quality)
            let left = geniusEngine.geniusLeft(60 + pc)
            let l = shell(left.quality)
            return (o.0, o.1, left.root, l.0, l.1, ChordQuality.allCases.firstIndex(of: left.quality) ?? 0)
        }
        kernel.publishGeniusTable(entries, oneFinger: of, lockShifts: locks, hands: hands)
        geniusVersion &+= 1
    }

    private func notifyStateChange() {
        if Thread.isMainThread { onStateChange?() } else {
            DispatchQueue.main.async { [weak self] in self?.onStateChange?() }
        }
    }

    /// Convenience used by the UI: sets a parameter so that the host sees the change too.
    public func set(_ address: ParamAddress, _ value: AUValue) {
        _parameterTree.parameter(withAddress: address.rawValue)?.setValue(value, originator: nil)
    }

    public func parameterValue(_ address: ParamAddress) -> AUValue {
        value(for: address.rawValue)
    }

    // MARK: - Presets: one factory preset per genre

    public override var factoryPresets: [AUAudioUnitPreset]? {
        Genre.all.enumerated().map { i, g in
            let p = AUAudioUnitPreset()
            p.number = i
            p.name = "\(g.emoji) \(g.name)"
            return p
        }
    }

    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            guard let preset = newValue else { _currentPreset = nil; return }
            if preset.number >= 0 {
                set(.genre, AUValue(preset.number))
                set(.keyRoot, 0)
                set(.complexity, AUValue(ChordComplexity.genre.rawValue))
                _currentPreset = preset
            } else {
                // User preset: let the default implementation restore the saved state.
                if let state = try? presetState(for: preset) { fullStateForDocument = state }
                _currentPreset = preset
            }
        }
    }

    // MARK: - Rendering

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = outputBus.format
        kernel.setup(sampleRate: format.sampleRate)
        renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender)
        kernel.midiOut = midiOutputEventBlock
        kernel.musicalContext = musicalContextBlock
        kernel.transportState = transportStateBlock
    }

    public override func deallocateRenderResources() {
        kernel.midiOut = nil
        kernel.musicalContext = nil
        kernel.transportState = nil
        renderBuffer = nil
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = self.kernel
        // Capture the buffer at block creation; it is re-created in allocateRenderResources.
        return { [weak self] _, timestamp, frameCount, _, outputData, realtimeEventListHead, _ in
            // If the host gives us no memory, render into our own buffer.
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            if let first = abl.first, first.mData == nil, let own = self?.renderBuffer {
                let ownList = UnsafeMutableAudioBufferListPointer(own.mutableAudioBufferList)
                for i in 0..<min(abl.count, ownList.count) {
                    abl[i].mData = ownList[i].mData
                    abl[i].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
                }
            }
            kernel.render(frameCount: frameCount, output: outputData, timestamp: timestamp,
                          events: realtimeEventListHead)
            return noErr
        }
    }
}
