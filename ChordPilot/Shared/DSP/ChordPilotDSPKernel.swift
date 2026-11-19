import Foundation
import AudioToolbox
import AVFoundation
import ChordPilotCore

/// One event of the genre-player loop as stored for the audio thread.
struct RawPatternEvent {
    var step: Int32
    var note: UInt8
    var velocity: UInt8
}

/// One synth voice. Harmonic phases live in the kernel's flat arrays (index = voice * 6 + harmonic).
struct PianoVoice {
    var active = false
    var note: Int32 = -1
    var lane: UInt8 = 0          // 0 = played by the user / host, 1 = genre player
    var gain: Float = 0
    var env: Float = 0
    var bright: Float = 1
    var attack: Float = 0
    var attackInc: Float = 0.01
    var decayCoef: Float = 0.9999
    var brightCoef: Float = 0.999
    var releaseCoef: Float = 0.999
    // FM (electric pianos)
    var fmPhase: Float = 0
    var fmInc: Float = 0
    var fmIndex: Float = 0
    var fmCoef: Float = 0.999
    // Detuned copy of the fundamental (honky-tonk / chorus)
    var detPhase: Float = 0
    var detInc: Float = 0
    var detAmp: Float = 0
    // Hammer / pluck noise
    var click: Float = 0
    var clickCoef: Float = 0.99
    var releasing = false
    var heldByPedal = false
    var age: UInt64 = 0
}

/// Real-time engine: polyphonic piano synth, MIDI routing (thru + output), and the genre player sequencer.
/// Everything touched from `render` is pre-allocated; no locks, no allocations, no Objective-C messaging.
final class ChordPilotDSPKernel {

    // MARK: Shared with the UI (read-only from the UI side)
    /// Velocity of each note the musician is currently holding (0 = not held).
    let heldNotes = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    /// Notes currently sounding from the genre player.
    let patternNotes = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    /// Index of the chord the genre player is on (written by the audio thread).
    private(set) var patternChordIndex: Int32 = 0
    /// Increments on every note-on so the UI can feed key detection without missing short notes.
    private(set) var noteOnCounter: UInt32 = 0
    let lastNotesRing = cp_ring_create(256)      // audio → UI: note-ons (for key detection)

    // MARK: UI → audio
    let uiRing = cp_ring_create(1024)           // packed MIDI messages from the on-screen keyboard
    let playRequest = cp_atomic_create(0)       // 1 = genre player should run
    private let patternPending = cp_atomic_create(-1)
    private let patternActive = cp_atomic_create(0)
    static let patternCapacity = 8192
    private let patternBuffers: [UnsafeMutablePointer<RawPatternEvent>]
    private let patternCounts = UnsafeMutablePointer<Int32>.allocate(capacity: 3)
    private let patternTotals = UnsafeMutablePointer<Int32>.allocate(capacity: 3)
    private let patternStepsPerChord = UnsafeMutablePointer<Int32>.allocate(capacity: 3)

    // MARK: Parameters (plain stores are fine for these scalar values)
    var volume: Float = 0.8
    var synthEnabled = true
    var hostSync = true
    var internalBPM: Double = 120
    var midiThru = true
    var isMIDIEffect = false

    // MARK: Host connections (set in allocateRenderResources)
    var midiOut: AUMIDIOutputEventBlock?
    var musicalContext: AUHostMusicalContextBlock?
    var transportState: AUHostTransportStateBlock?

    // MARK: Audio-thread state
    private let maxVoices = 32
    private let voices: UnsafeMutablePointer<PianoVoice>
    private var sampleRate: Double = 44100
    private var voiceAge: UInt64 = 0
    private var sustain = false
    private var isPlaying = false
    private var stepPhase: Double = 0
    private var nextStep: Int = 0
    private var cursor: Int = 0
    private let midiBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
    private var smoothedVolume: Float = 0.8

    init() {
        voices = UnsafeMutablePointer<PianoVoice>.allocate(capacity: maxVoices)
        voices.initialize(repeating: PianoVoice(), count: maxVoices)
        heldNotes.initialize(repeating: 0, count: 128)
        patternNotes.initialize(repeating: 0, count: 128)
        patternBuffers = (0..<3).map { _ in
            let p = UnsafeMutablePointer<RawPatternEvent>.allocate(capacity: ChordPilotDSPKernel.patternCapacity)
            p.initialize(repeating: RawPatternEvent(step: 0, note: 0, velocity: 0), count: ChordPilotDSPKernel.patternCapacity)
            return p
        }
        patternCounts.initialize(repeating: 0, count: 3)
        patternTotals.initialize(repeating: 16, count: 3)
        patternStepsPerChord.initialize(repeating: 16, count: 3)
        midiBytes.initialize(repeating: 0, count: 3)
        prepareBuffers()
    }

    deinit {
        voices.deallocate()
        heldNotes.deallocate()
        patternNotes.deallocate()
        patternBuffers.forEach { $0.deallocate() }
        patternCounts.deallocate()
        patternTotals.deallocate()
        patternStepsPerChord.deallocate()
        midiBytes.deallocate()
        modelTable.deallocate()
        partialPhase.deallocate(); partialInc.deallocate(); partialAmp.deallocate()
        cp_ring_destroy(uiRing)
        cp_ring_destroy(lastNotesRing)
        cp_atomic_destroy(playRequest)
        cp_atomic_destroy(patternPending)
        cp_atomic_destroy(patternActive)
    }

    func setup(sampleRate: Double) {
        self.sampleRate = sampleRate
        for i in 0..<maxVoices { voices[i] = PianoVoice() }
        for n in 0..<128 { heldNotes[n] = 0; patternNotes[n] = 0 }
        isPlaying = false
        sustain = false
    }

    // MARK: - UI side API (main thread)

    func sendFromUI(status: UInt8, data1: UInt8, data2: UInt8) {
        let packed = UInt32(status) | (UInt32(data1 & 0x7F) << 8) | (UInt32(data2 & 0x7F) << 16)
        _ = cp_ring_push(uiRing, packed)
    }

    /// Publishes a new loop for the genre player (triple buffered, never blocks the audio thread).
    func publishPattern(events: [(step: Int, note: UInt8, velocity: UInt8)], totalSteps: Int, stepsPerChord: Int) {
        let active = cp_atomic_load(patternActive)
        let pending = cp_atomic_load(patternPending)
        var target: Int32 = 0
        while target == active || target == pending { target += 1 }
        let idx = Int(target)
        let count = min(events.count, ChordPilotDSPKernel.patternCapacity)
        let buf = patternBuffers[idx]
        for i in 0..<count {
            let e = events[i]
            buf[i] = RawPatternEvent(step: Int32(e.step), note: e.note, velocity: e.velocity)
        }
        patternCounts[idx] = Int32(count)
        patternTotals[idx] = Int32(max(1, totalSteps))
        patternStepsPerChord[idx] = Int32(max(1, stepsPerChord))
        cp_atomic_store(patternPending, target)
    }

    var playerRunning: Bool { isPlaying }

    // MARK: - Render (audio thread)

    func render(frameCount: AUAudioFrameCount,
                output: UnsafeMutablePointer<AudioBufferList>,
                timestamp: UnsafePointer<AudioTimeStamp>,
                events: UnsafePointer<AURenderEvent>?) {
        let frames = Int(frameCount)
        let abl = UnsafeMutableAudioBufferListPointer(output)
        for buffer in abl {
            if let d = buffer.mData { memset(d, 0, Int(buffer.mDataByteSize)) }
        }
        let sampleTime = timestamp.pointee.mSampleTime

        // 1. Pattern swap & transport.
        let pending = cp_atomic_exchange(patternPending, -1)
        if pending >= 0 {
            releasePatternNotes(at: 0, sampleTime: sampleTime)
            cp_atomic_store(patternActive, pending)
            seekCursor(toStep: nextStep)
        }
        let active = Int(cp_atomic_load(patternActive))
        let total = Int(patternTotals[active])
        let count = Int(patternCounts[active])
        let buf = patternBuffers[active]

        var tempo = internalBPM
        var hostMoving = false
        var hostBeat: Double = 0
        var hasHostClock = false
        if hostSync, let ctx = musicalContext {
            var t: Double = 0, beat: Double = 0
            if ctx(&t, nil, nil, &beat, nil, nil), t > 0 {
                tempo = t
                hostBeat = beat
                hasHostClock = true
            }
            if let ts = transportState {
                var flags = AUHostTransportStateFlags()
                if ts(&flags, nil, nil, nil) { hostMoving = flags.contains(.moving) }
            }
        }
        let wantPlay = cp_atomic_load(playRequest) != 0
        // Follow the DAW's timeline while it plays; otherwise run on our own clock (at the host tempo if known).
        let followHost = hasHostClock && hostMoving
        let shouldPlay = wantPlay
        if shouldPlay && !isPlaying {
            isPlaying = true
            stepPhase = followHost ? hostBeat * 4 : 0
            nextStep = Int(ceil(stepPhase - 1e-9))
            seekCursor(toStep: nextStep)
        } else if !shouldPlay && isPlaying {
            isPlaying = false
            releasePatternNotes(at: 0, sampleTime: sampleTime)
        }
        let samplesPerStep = sampleRate * 60.0 / max(20, tempo) / 4.0
        if isPlaying && followHost {
            let hostPhase = hostBeat * 4
            if abs(hostPhase - stepPhase) > 0.5 {     // host jumped (loop / locate)
                releasePatternNotes(at: 0, sampleTime: sampleTime)
                stepPhase = hostPhase
                nextStep = Int(ceil(stepPhase - 1e-9))
                seekCursor(toStep: nextStep)
            }
        }
        let phaseStart = stepPhase
        let phaseEnd = stepPhase + Double(frames) / samplesPerStep

        // 2. On-screen keyboard events (applied at the start of the buffer).
        var msg: UInt32 = 0
        while cp_ring_pop(uiRing, &msg) {
            handleMIDI(UInt8(msg & 0xFF), UInt8((msg >> 8) & 0x7F), UInt8((msg >> 16) & 0x7F),
                       offset: 0, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: true)
        }

        // 3. Interleave host events, sequencer steps and synthesis, sample-accurately.
        var done = 0
        var event = events
        while done < frames {
            var nextEventOffset = frames
            if let e = event {
                let off = Int(e.pointee.head.eventSampleTime - AUEventSampleTime(sampleTime))
                nextEventOffset = max(done, min(frames - 1, off))
            }
            var nextStepOffset = frames
            if isPlaying && total > 0 && Double(nextStep) < phaseEnd {
                let off = Int(ceil((Double(nextStep) - phaseStart) * samplesPerStep))
                nextStepOffset = max(done, min(frames - 1, off))
            }
            let next = min(nextEventOffset, nextStepOffset)
            if next > done {
                synthesize(abl, from: done, to: next)
                done = next
            }
            if next >= frames { break }
            if nextEventOffset == next, let e = event {
                handleRenderEvent(e, offset: next, sampleTime: sampleTime)
                event = UnsafePointer(e.pointee.head.next)
            }
            if nextStepOffset == next && isPlaying && total > 0 && Double(nextStep) < phaseEnd {
                fireStep(nextStep % total, buffer: buf, count: count, offset: next, sampleTime: sampleTime,
                         stepsPerChord: Int(patternStepsPerChord[active]))
                nextStep += 1
            }
        }
        // Any events left at the very end of the buffer.
        while let e = event {
            handleRenderEvent(e, offset: frames - 1, sampleTime: sampleTime)
            event = UnsafePointer(e.pointee.head.next)
        }
        if isPlaying { stepPhase = phaseEnd }
        if nextStep > 1_000_000_000 { nextStep = nextStep % max(1, total); stepPhase = Double(nextStep) }
    }

    private func handleRenderEvent(_ e: UnsafePointer<AURenderEvent>, offset: Int, sampleTime: Float64) {
        switch e.pointee.head.eventType {
        case .MIDI:
            let m = e.pointee.MIDI
            guard m.length > 0 else { return }
            handleMIDI(m.data.0, m.data.1, m.data.2, offset: offset, sampleTime: sampleTime,
                       fromPattern: false, forward: true)
        case .parameter, .parameterRamp:
            let p = e.pointee.parameter
            applyRenderParameter(address: p.parameterAddress, value: p.value)
        default:
            break
        }
    }

    /// Only real-time-safe parameters are applied from scheduled render events.
    private func applyRenderParameter(address: AUParameterAddress, value: AUValue) {
        switch address {
        case ParamAddress.volume.rawValue: volume = value
        case ParamAddress.synth.rawValue: synthEnabled = value > 0.5
        case ParamAddress.hostSync.rawValue: hostSync = value > 0.5
        case ParamAddress.play.rawValue: cp_atomic_store(playRequest, value > 0.5 ? 1 : 0)
        case ParamAddress.bpm.rawValue: internalBPM = Double(value)
        case ParamAddress.piano.rawValue: pianoType = Int(value.rounded())
        default: break
        }
    }

    private func seekCursor(toStep step: Int) {
        let active = Int(cp_atomic_load(patternActive))
        let total = max(1, Int(patternTotals[active]))
        let count = Int(patternCounts[active])
        let s = Int32(((step % total) + total) % total)
        let buf = patternBuffers[active]
        var i = 0
        while i < count && buf[i].step < s { i += 1 }
        cursor = i
    }

    private func fireStep(_ step: Int, buffer: UnsafeMutablePointer<RawPatternEvent>, count: Int,
                          offset: Int, sampleTime: Float64, stepsPerChord: Int) {
        if step == 0 { cursor = 0 }
        patternChordIndex = Int32(step / max(1, stepsPerChord))
        let s = Int32(step)
        while cursor < count && buffer[cursor].step < s { cursor += 1 }
        while cursor < count && buffer[cursor].step == s {
            let e = buffer[cursor]
            if e.velocity > 0 {
                handleMIDI(0x90, e.note, e.velocity, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true)
            } else if patternNotes[Int(e.note)] > 0 {
                handleMIDI(0x80, e.note, 0, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true)
            }
            cursor += 1
        }
    }

    private func releasePatternNotes(at offset: Int, sampleTime: Float64) {
        for n in 0..<128 where patternNotes[n] > 0 {
            handleMIDI(0x80, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true)
        }
    }

    // MARK: MIDI

    /// - fromUI: generated by the on-screen keyboard or a tapped suggestion (always sent to MIDI out).
    /// - fromPattern: generated by the genre player (always sent to MIDI out).
    /// Host / external MIDI is echoed to MIDI out only when `midiThru` is on (needed for MIDI FX chains,
    /// off in the standalone app so a digital piano does not hear its own notes twice).
    private func handleMIDI(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, offset: Int, sampleTime: Float64,
                            fromPattern: Bool, forward: Bool, fromUI: Bool = false) {
        let type = status & 0xF0
        let note = Int(d1 & 0x7F)
        switch type {
        case 0x90 where d2 > 0:
            if fromPattern { patternNotes[note] = d2 } else {
                heldNotes[note] = d2
                noteOnCounter &+= 1
                _ = cp_ring_push(lastNotesRing, UInt32(note) | (UInt32(d2) << 8))
            }
            if synthEnabled && !isMIDIEffect { noteOn(note, velocity: d2, lane: fromPattern ? 1 : 0) }
        case 0x80, 0x90:
            if fromPattern { patternNotes[note] = 0 } else { heldNotes[note] = 0 }
            noteOff(note, lane: fromPattern ? 1 : 0)
        case 0xB0:
            if d1 == 64 {
                sustain = d2 >= 64
                if !sustain { releasePedalNotes() }
            } else if d1 == 120 || d1 == 123 {
                allNotesOff()
            }
        default:
            break
        }
        if forward && (midiThru || fromPattern || fromUI), let out = midiOut {
            midiBytes[0] = status; midiBytes[1] = d1; midiBytes[2] = d2
            let len = (type == 0xC0 || type == 0xD0) ? 2 : 3
            _ = out(AUEventSampleTime(sampleTime) + AUEventSampleTime(offset), 0, len, midiBytes)
        }
    }

    private func allNotesOff() {
        for i in 0..<maxVoices where voices[i].active {
            voices[i].releasing = true
            voices[i].heldByPedal = false
        }
        for n in 0..<128 { heldNotes[n] = 0 }
    }

    // MARK: Synth

    /// Flattened copy of `PianoModel.all` so the audio thread never touches Swift arrays.
    static let modelStride = 18
    private let modelTable: UnsafeMutablePointer<Float> = {
        let models = PianoModel.all
        let t = UnsafeMutablePointer<Float>.allocate(capacity: models.count * ChordPilotDSPKernel.modelStride)
        for (i, m) in models.enumerated() {
            let b = i * ChordPilotDSPKernel.modelStride
            for k in 0..<6 { t[b + k] = k < m.partials.count ? m.partials[k] : 0 }
            t[b + 6] = m.inharmonicity; t[b + 7] = m.decay; t[b + 8] = m.brightDecay; t[b + 9] = m.release
            t[b + 10] = m.attack; t[b + 11] = m.detuneCents; t[b + 12] = m.fmRatio; t[b + 13] = m.fmIndex
            t[b + 14] = m.fmDecay; t[b + 15] = m.click; t[b + 16] = m.velocityBrightness; t[b + 17] = m.gain
        }
        return t
    }()
    /// Selected piano (index into `PianoModel.all`). Read once per note-on.
    var pianoType: Int = 0
    private let modelCount = PianoModel.all.count
    private lazy var partialPhase = Self.makeBuffer(maxVoices * 6)
    private lazy var partialInc = Self.makeBuffer(maxVoices * 6)
    private lazy var partialAmp = Self.makeBuffer(maxVoices * 6)
    private var noiseSeed: UInt32 = 22222

    private static func makeBuffer(_ n: Int) -> UnsafeMutablePointer<Float> {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
        p.initialize(repeating: 0, count: n)
        return p
    }

    /// Must be called once from `init`-time code paths before rendering (touches the lazy buffers).
    func prepareBuffers() {
        _ = partialPhase; _ = partialInc; _ = partialAmp
    }

    private func noteOn(_ note: Int, velocity: UInt8, lane: UInt8) {
        // Re-use a voice already playing this note in the same lane, else a free one, else the oldest.
        var slot = -1
        var oldest = UInt64.max
        var oldestIdx = 0
        for i in 0..<maxVoices {
            let v = voices[i]
            if v.active && v.note == Int32(note) && v.lane == lane { slot = i; break }
            if !v.active && slot < 0 { slot = i }
            let score = v.releasing ? v.age / 2 : v.age
            if v.active && score < oldest { oldest = score; oldestIdx = i }
        }
        if slot < 0 { slot = oldestIdx }
        voiceAge &+= 1

        let mi = max(0, min(modelCount - 1, pianoType))
        let m = modelTable + mi * Self.modelStride
        let sr = Float(sampleRate)
        let f0 = Float(440.0 * pow(2.0, (Double(note) - 69.0) / 12.0))
        let vel = Float(velocity) / 127.0
        // Lower notes ring longer, higher notes decay faster - like real strings.
        let keyScale = max(0.18, 1.0 - Float(note - 21) * 0.0105)
        let decaySeconds = max(0.25, m[7] * keyScale)
        let velBright = 1 - m[16] + m[16] * vel
        let nyquist = sr * 0.45

        let base = slot * 6
        for k in 0..<6 {
            let h = Float(k + 1)
            let freq = f0 * h * sqrtf(1 + m[6] * h * h)
            partialInc[base + k] = freq / sr
            // Harmonics above Nyquist are muted (no aliasing); higher harmonics follow velocity.
            partialAmp[base + k] = freq < nyquist ? m[k] * (k == 0 ? 1 : powf(velBright, Float(k) * 0.6)) : 0
            if !voices[slot].active { partialPhase[base + k] = 0 }
        }
        let wasActive = voices[slot].active
        var v = PianoVoice()
        v.active = true
        v.note = Int32(note)
        v.lane = lane
        v.gain = (0.12 + 0.88 * vel * vel) * m[17] * (lane == 1 ? 0.75 : 1.0)
        v.env = 1
        v.bright = 1
        // A re-triggered voice continues from its current level instead of clicking to zero.
        v.attack = wasActive ? min(1, voices[slot].env * voices[slot].attack) : 0
        v.attackInc = 1.0 / max(1, m[10] * sr)
        v.decayCoef = expf(-1.0 / (decaySeconds * sr))
        v.brightCoef = expf(-1.0 / (max(0.05, m[8] * decaySeconds) * sr))
        v.releaseCoef = expf(-1.0 / (max(0.02, m[9] * 0.4) * sr))
        v.fmInc = m[12] > 0 ? f0 * m[12] / sr : 0
        v.fmIndex = m[13] * (0.35 + 0.65 * vel)
        v.fmCoef = expf(-1.0 / (max(0.01, m[14]) * sr))
        v.fmPhase = wasActive ? voices[slot].fmPhase : 0
        if m[11] > 0 {
            v.detInc = f0 * powf(2, m[11] / 1200) / sr
            v.detAmp = m[11] > 8 ? 0.7 : 0.35
            v.detPhase = wasActive ? voices[slot].detPhase : 0.25
        }
        v.click = m[15] * (0.4 + 0.6 * vel)
        v.clickCoef = expf(-1.0 / (0.004 * sr))
        v.age = voiceAge
        voices[slot] = v
    }

    private func noteOff(_ note: Int, lane: UInt8) {
        for i in 0..<maxVoices where voices[i].active && voices[i].note == Int32(note) && voices[i].lane == lane
            && !voices[i].releasing {
            if sustain && lane == 0 { voices[i].heldByPedal = true } else { voices[i].releasing = true }
        }
    }

    private func releasePedalNotes() {
        for i in 0..<maxVoices where voices[i].active && voices[i].heldByPedal {
            voices[i].heldByPedal = false
            voices[i].releasing = true
        }
    }

    private func synthesize(_ abl: UnsafeMutableAudioBufferListPointer, from start: Int, to end: Int) {
        guard abl.count > 0, let left = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let twoPi: Float = 2 * .pi
        let target = synthEnabled && !isMIDIEffect ? volume : 0
        for i in 0..<maxVoices where voices[i].active {
            var v = voices[i]
            let base = i * 6
            let pan = 0.5 + Float(Int(v.note) - 60) * 0.008
            let gl = cosf(pan * .pi / 2), gr = sinf(pan * .pi / 2)
            let a0 = partialAmp[base], a1 = partialAmp[base + 1], a2 = partialAmp[base + 2]
            let a3 = partialAmp[base + 3], a4 = partialAmp[base + 4], a5 = partialAmp[base + 5]
            let i0 = partialInc[base], i1 = partialInc[base + 1], i2 = partialInc[base + 2]
            let i3 = partialInc[base + 3], i4 = partialInc[base + 4], i5 = partialInc[base + 5]
            var p0 = partialPhase[base], p1 = partialPhase[base + 1], p2 = partialPhase[base + 2]
            var p3 = partialPhase[base + 3], p4 = partialPhase[base + 4], p5 = partialPhase[base + 5]
            for f in start..<end {
                if v.attack < 1 { v.attack = min(1, v.attack + v.attackInc) }
                v.env *= v.releasing ? v.releaseCoef : v.decayCoef
                v.bright *= v.brightCoef
                let b = v.bright
                // Fundamental, optionally frequency-modulated (electric pianos).
                var fm: Float = 0
                if v.fmInc > 0 {
                    fm = v.fmIndex * sinf(v.fmPhase * twoPi)
                    v.fmIndex *= v.fmCoef
                    v.fmPhase += v.fmInc
                    if v.fmPhase >= 1 { v.fmPhase -= floorf(v.fmPhase) }
                }
                var s = a0 * sinf(p0 * twoPi + fm)
                if a1 > 0 { s += a1 * b * sinf(p1 * twoPi) }
                if a2 > 0 { s += a2 * b * b * sinf(p2 * twoPi) }
                if a3 > 0 { s += a3 * b * b * sinf(p3 * twoPi) }
                if a4 > 0 { s += a4 * b * b * b * sinf(p4 * twoPi) }
                if a5 > 0 { s += a5 * b * b * b * sinf(p5 * twoPi) }
                if v.detAmp > 0 {
                    s += v.detAmp * a0 * sinf(v.detPhase * twoPi)
                    v.detPhase += v.detInc
                    if v.detPhase >= 1 { v.detPhase -= 1 }
                }
                if v.click > 0.0001 {
                    noiseSeed = noiseSeed &* 1664525 &+ 1013904223
                    s += v.click * (Float(noiseSeed >> 9) / 4194304.0 - 1.0)
                    v.click *= v.clickCoef
                }
                let out = s * v.gain * v.attack * v.env * 0.6
                left[f] += out * gl
                right?[f] += out * gr
                p0 += i0; if p0 >= 1 { p0 -= 1 }
                p1 += i1; if p1 >= 1 { p1 -= 1 }
                p2 += i2; if p2 >= 1 { p2 -= 1 }
                p3 += i3; if p3 >= 1 { p3 -= 1 }
                p4 += i4; if p4 >= 1 { p4 -= 1 }
                p5 += i5; if p5 >= 1 { p5 -= 1 }
            }
            partialPhase[base] = p0; partialPhase[base + 1] = p1; partialPhase[base + 2] = p2
            partialPhase[base + 3] = p3; partialPhase[base + 4] = p4; partialPhase[base + 5] = p5
            if v.releasing && v.env < 0.0005 { v.active = false }
            if !v.releasing && v.env < 0.0003 { v.active = false }
            voices[i] = v
        }
        // Volume smoothing + soft clip.
        for f in start..<end {
            smoothedVolume += (target - smoothedVolume) * 0.002
            let g = smoothedVolume * 0.35
            left[f] = softClip(left[f] * g)
            if let r = right { r[f] = softClip(r[f] * g) }
        }
    }

    @inline(__always) private func softClip(_ x: Float) -> Float {
        if x > 1 { return 1 }
        if x < -1 { return -1 }
        return x - (x * x * x) / 3 * 0.5
    }
}

/// Parameter addresses shared by the Audio Unit, the UI and the host.
public enum ParamAddress: AUParameterAddress {
    case genre = 0, keyRoot, keyMinor, complexity, volume, synth, hostSync, play, progression, bpm, piano
}
