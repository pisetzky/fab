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
        setupParameters()
        rebuildPattern()
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
            p("bpm", "BPM", .bpm, 40, 220, .BPM)
        ]
        params[Int(ParamAddress.volume.rawValue)].value = 0.8
        params[Int(ParamAddress.synth.rawValue)].value = kernel.isMIDIEffect ? 0 : 1
        params[Int(ParamAddress.hostSync.rawValue)].value = 1
        params[Int(ParamAddress.bpm.rawValue)].value = AUValue(genre.bpm)
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

    private func rebuildPattern() {
        let p = GenrePatternBuilder.build(genre: genre, key: playerKey, progressionIndex: progressionIndex,
                                          complexity: complexity)
        currentPattern = p
        kernel.publishPattern(events: p.events.map { ($0.step, $0.note, $0.velocity) },
                              totalSteps: p.totalSteps, stepsPerChord: 16 * max(1, genre.barsPerChord))
        notifyStateChange()
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
