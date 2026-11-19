import Foundation
import AudioToolbox
import AVFoundation
import ChordPilotCore

/// One event of the genre-player loop as stored for the audio thread.
struct RawPatternEvent {
    var step: Int32
    var note: UInt8
    var velocity: UInt8
    var lane: UInt8 = 0      // 0 = chords / bass (MIDI ch 1), 1 = melody (MIDI ch 2)
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
    /// Notes currently sounding from the genre player (accompaniment and melody).
    let patternNotes = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    let melodyNotes = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    /// Index of the chord the genre player is on (written by the audio thread).
    private(set) var patternChordIndex: Int32 = 0
    /// Increments on every note-on so the UI can feed key detection without missing short notes.
    private(set) var noteOnCounter: UInt32 = 0
    let lastNotesRing = cp_ring_create(256)      // audio → UI: note-ons (for key detection)
    let geniusRing = cp_ring_create(256)         // audio → AU: genius notes (0x10000|n) and chords (0x20000|root<<8|quality)

    // MARK: Genius mode (table of 12 pitch classes × 8 ints, triple buffered)
    var geniusEnabled = false
    static let geniusStride = 17                 // genius: shift, root, numTones, tones[5], quality | one-finger: root, numTones, tones[5] | lockShift
    private let geniusTables: [UnsafeMutablePointer<Int32>] = (0..<3).map { _ in
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: 12 * 17); p.initialize(repeating: 0, count: 204); return p }
    private let geniusPending = cp_atomic_create(-1)
    private let geniusActive = cp_atomic_create(0)
    private var geniusHasTable = false
    private let pressedToSounding = UnsafeMutablePointer<Int16>.allocate(capacity: 128)
    private let gNotes = UnsafeMutablePointer<Int32>.allocate(capacity: 8)
    private var gCount = 0
    private let gTones = UnsafeMutablePointer<Int32>.allocate(capacity: 6)
    private var gNumTones = 0
    private var gChordOn = false
    private var gChangedAt: Int64 = -1_000_000
    private var lastNoteAt: Int64 = 0
    private var sampleClock: Int64 = 0

    // MARK: Pro options (Scaler / Captain Chords / InstaChord-style extras)
    var oneFingerEnabled = false
    var scaleLockEnabled = false
    var transpose = 0
    var strumMs: Double = 0
    var humanize: Double = 0        // 0...1
    var swing: Double = 0           // 0...0.6
    var voicingStyle = 0
    // Genre drums: 3 lanes × 16 steps (written by the AU on genre change), synthesised voices.
    var drumsEnabled = false
    let drumLanes: UnsafeMutablePointer<UInt8> = {
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: 48); p.initialize(repeating: 0, count: 48); return p }()
    private var drumT = [Float](repeating: 1e9, count: 3)
    private var drumVel = [Float](repeating: 0, count: 3)
    private var drumPhase = [Float](repeating: 0, count: 3)
    private var drumLP = [Float](repeating: 0, count: 3)
    private var inTransform = false
    private let ofScratch: UnsafeMutablePointer<Int32> = {
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: 12); p.initialize(repeating: 0, count: 12); return p }()
    private var lastTempo: Double = 120
    private var randomState: UInt32 = 0x1234567
    struct Delayed { var due: Int64 = 0; var status: UInt8 = 0; var note: UInt8 = 0; var vel: UInt8 = 0; var pattern = false; var active = false }
    private let delayed: UnsafeMutablePointer<Delayed> = {
        let p = UnsafeMutablePointer<Delayed>.allocate(capacity: 1024); p.initialize(repeating: Delayed(), count: 1024); return p }()
    private let oneFingerHeld: UnsafeMutablePointer<Int32> = {   // 128 keys × (count + 9 notes)
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: 128 * 10); p.initialize(repeating: 0, count: 1280); return p }()

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
        melodyNotes.initialize(repeating: 0, count: 128)
        pressedToSounding.initialize(repeating: -1, count: 128)
        gNotes.initialize(repeating: 0, count: 8)
        gTones.initialize(repeating: 0, count: 6)
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
        melodyNotes.deallocate()
        pressedToSounding.deallocate(); gNotes.deallocate(); gTones.deallocate()
        geniusTables.forEach { $0.deallocate() }
        cp_ring_destroy(geniusRing); cp_atomic_destroy(geniusPending); cp_atomic_destroy(geniusActive)
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
        for n in 0..<128 { heldNotes[n] = 0; patternNotes[n] = 0; melodyNotes[n] = 0; pressedToSounding[n] = -1 }
        gCount = 0; gChordOn = false
        isPlaying = false
        sustain = false
    }

    // MARK: - UI side API (main thread)

    func sendFromUI(status: UInt8, data1: UInt8, data2: UInt8) {
        let packed = UInt32(status) | (UInt32(data1 & 0x7F) << 8) | (UInt32(data2 & 0x7F) << 16)
        _ = cp_ring_push(uiRing, packed)
    }

    /// Publishes a new loop for the genre player (triple buffered, never blocks the audio thread).
    /// Publishes the genius lookup table: for each pitch class (shift, chord root, chord tones).
    func publishGeniusTable(_ entries: [(shift: Int, root: Int, quality: Int, tones: [Int])],
                            oneFinger: [(root: Int, tones: [Int])] = [], lockShifts: [Int] = []) {
        let active = cp_atomic_load(geniusActive), pending = cp_atomic_load(geniusPending)
        var target: Int32 = 0
        while target == active || target == pending { target += 1 }
        let t = geniusTables[Int(target)]
        for (pc, e) in entries.prefix(12).enumerated() {
            let b = pc * Self.geniusStride
            t[b] = Int32(e.shift); t[b + 1] = Int32(e.root)
            let tones = e.tones.prefix(5)
            t[b + 2] = Int32(tones.count); t[b + 8] = Int32(e.quality)
            for (i, x) in tones.enumerated() { t[b + 3 + i] = Int32(x) }
            if pc < oneFinger.count {
                let of = oneFinger[pc], ot = of.tones.prefix(5)
                t[b + 9] = Int32(of.root); t[b + 10] = Int32(ot.count)
                for (i, x) in ot.enumerated() { t[b + 11 + i] = Int32(x) }
            }
            t[b + 16] = pc < lockShifts.count ? Int32(lockShifts[pc]) : 0
        }
        cp_atomic_store(geniusPending, target)
    }

    func publishPattern(events: [(step: Int, note: UInt8, velocity: UInt8, lane: UInt8)], totalSteps: Int, stepsPerChord: Int) {
        let active = cp_atomic_load(patternActive)
        let pending = cp_atomic_load(patternPending)
        var target: Int32 = 0
        while target == active || target == pending { target += 1 }
        let idx = Int(target)
        let count = min(events.count, ChordPilotDSPKernel.patternCapacity)
        let buf = patternBuffers[idx]
        for i in 0..<count {
            let e = events[i]
            buf[i] = RawPatternEvent(step: Int32(e.step), note: e.note, velocity: e.velocity, lane: e.lane)
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
            for i in 0..<1024 where delayed[i].pattern { delayed[i].active = false }
            releasePatternNotes(at: 0, sampleTime: sampleTime)
        }
        let samplesPerStep = sampleRate * 60.0 / max(20, tempo) / 4.0
        lastTempo = tempo
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

        let gp = cp_atomic_exchange(geniusPending, -1)
        if gp >= 0 { cp_atomic_store(geniusActive, gp); geniusHasTable = true }

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
            let nextDelayed = nextDelayedOffset(done: done, frames: frames)
            let next = min(nextEventOffset, nextStepOffset, nextDelayed)
            if next > done {
                synthesize(abl, from: done, to: next)
                done = next
            }
            if next >= frames { break }
            if nextDelayed == next { runDelayed(offset: next, sampleTime: sampleTime) }
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
        // Genius chord fades out 1.8 s after the last key is released.
        if gChordOn {
            var anyHeld = false
            for n in 0..<128 where heldNotes[n] > 0 { anyHeld = true; break }
            if !geniusEnabled || (!anyHeld && sampleClock + Int64(frames) - lastNoteAt > Int64(1.8 * sampleRate)) {
                geniusChordOff(offset: frames - 1, sampleTime: sampleTime)
            } else if anyHeld { lastNoteAt = sampleClock + Int64(frames) }
        }
        sampleClock += Int64(frames)
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
        if drumsEnabled {
            let notes: [UInt8] = [36, 38, 42]
            for k in 0..<3 where drumLanes[k * 16 + step % 16] != 0 {
                let vel: UInt8 = k == 2 ? (step % 4 == 0 ? 70 : 50) : (step % 16 == 0 ? 110 : 96)
                if synthEnabled && !isMIDIEffect { drumT[k] = 0; drumVel[k] = Float(vel) / 127; drumPhase[k] = 0 }
                sendOut(0x99, notes[k], vel, offset: offset, sampleTime: sampleTime)          // MIDI channel 10
                sendOut(0x89, notes[k], 0, offset: min(offset + 1, 4095), sampleTime: sampleTime)
            }
        }
        let s = Int32(step)
        while cursor < count && buffer[cursor].step < s { cursor += 1 }
        // Pro: swing, strum and humanize go through the delayed-event queue.
        if swing > 0 || strumMs > 0 || humanize > 0 {
            let spStep = sampleRate * 60.0 / max(20, lastTempo) / 4.0
            let base = sampleClock + Int64(offset) + (step % 2 == 1 ? Int64(spStep * swing) : 0)
            var chordIdx: Int64 = 0
            while cursor < count && buffer[cursor].step == s {
                let e = buffer[cursor]
                let ch: UInt8 = e.lane == 1 ? 1 : 0
                if e.velocity > 0 {
                    let st: Int64 = e.lane == 1 ? 0 : Int64(strumMs / 1000 * sampleRate) * chordIdx
                    if e.lane != 1 { chordIdx += 1 }
                    enqueue(due: base + st + humanDelay(), status: 0x90 | ch, note: e.note, vel: humanVel(e.velocity), pattern: true)
                } else {
                    enqueue(due: base, status: 0x80 | ch, note: e.note, vel: 0, pattern: true)
                }
                cursor += 1
            }
            return
        }
        while cursor < count && buffer[cursor].step == s {
            let e = buffer[cursor]
            let ch: UInt8 = e.lane == 1 ? 1 : 0
            let arr = e.lane == 1 ? melodyNotes : patternNotes
            if e.velocity > 0 {
                handleMIDI(0x90 | ch, e.note, e.velocity, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true)
            } else if arr[Int(e.note)] > 0 {
                handleMIDI(0x80 | ch, e.note, 0, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true)
            }
            cursor += 1
        }
    }

    private func releasePatternNotes(at offset: Int, sampleTime: Float64) {
        for n in 0..<128 {
            if patternNotes[n] > 0 { handleMIDI(0x80, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true) }
            if melodyNotes[n] > 0 { handleMIDI(0x81, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: true, forward: true) }
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
        let channel = status & 0x0F
        // Genius mode: user notes become the closest fitting note, harmonised by the next chord.
        if !fromPattern && !inTransform && channel != 15 && (type == 0x90 || type == 0x80)
            && (transpose != 0 || ((oneFingerEnabled || scaleLockEnabled || geniusEnabled) && geniusHasTable)) {
            inTransform = true
            transformInput(status, d1, d2, offset: offset, sampleTime: sampleTime, fromUI: fromUI)
            inTransform = false
            return
        }
        let note = Int(d1 & 0x7F)
        let suggestionLane = !fromPattern && channel == 15      // tapped suggestions use MIDI channel 16
        let melodyLane = fromPattern && channel == 1
        let synthLane: UInt8 = fromPattern ? (melodyLane ? 3 : 1) : (suggestionLane ? 2 : 0)
        switch type {
        case 0x90 where d2 > 0:
            if fromPattern { (melodyLane ? melodyNotes : patternNotes)[note] = d2 } else if !suggestionLane {
                heldNotes[note] = d2
                noteOnCounter &+= 1
                _ = cp_ring_push(lastNotesRing, UInt32(note) | (UInt32(d2) << 8))
            }
            if synthEnabled && !isMIDIEffect { noteOn(note, velocity: d2, lane: synthLane) }
        case 0x80, 0x90:
            if fromPattern { (melodyLane ? melodyNotes : patternNotes)[note] = 0 } else if !suggestionLane { heldNotes[note] = 0 }
            noteOff(note, lane: synthLane)
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

    /// User-note pipeline: transpose → one-finger chords / Genius mode / scale lock.
    private func transformInput(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, offset: Int, sampleTime: Float64, fromUI: Bool) {
        let ch = status & 0x0F
        let isOff = status & 0xF0 == 0x80 || d2 == 0
        let raw = Int(d1 & 0x7F)
        let pressed = max(0, min(127, raw + transpose))
        let table = geniusTables[Int(cp_atomic_load(geniusActive))]
        if oneFingerEnabled && geniusHasTable {
            let slot = oneFingerHeld + raw * 10
            if isOff {
                for i in 0..<Int(slot[0]) {
                    let n = slot[1 + i]
                    var still = false
                    for k in 0..<128 where k != raw {
                        let o = oneFingerHeld + k * 10
                        for j in 0..<Int(o[0]) where o[1 + j] == n { still = true }
                    }
                    if !still { handleMIDI(0x80 | ch, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI) }
                }
                slot[0] = 0
                return
            }
            let t = table + (pressed % 12) * Self.geniusStride
            let root = Int(t[9]), nt = Int(t[10])
            var r = pressed
            while r % 12 != root { r -= 1 }
            // stack the chord tones on the root, then apply the voicing style and add the bass (no allocation)
            let notes = ofScratch
            var nn = 0
            var last = r - 1
            for i in -1..<nt {
                let tone = i < 0 ? root : Int(t[11 + i])
                if i >= 0 && tone == root { continue }
                var n = last + 1
                while n % 12 != tone { n += 1 }
                notes[nn] = Int32(n); nn += 1; last = n
            }
            let style = max(1, voicingStyle)
            if style == 2 && nn >= 3 { notes[1] += 12 }
            if style == 3 && nn >= 4 { notes[nn - 2] -= 12 }
            if style == 4 && nn > 1 { for i in 1..<nn { notes[i] += 12 } }
            notes[nn] = Int32(r - 12); nn += 1
            var count = 0
            for k in 0..<nn where notes[k] >= 21 && notes[k] <= 108 && count < 9 {
                let n = notes[k]
                var dup = false
                for j in 0..<count where slot[1 + j] == n { dup = true }
                if dup { continue }
                slot[1 + count] = n
                let delay = Int64(strumMs / 1000 * sampleRate) * Int64(count) + humanDelay()
                let vel = humanVel(d2)
                if delay == 0 {
                    handleMIDI(0x90 | ch, UInt8(n), vel, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI)
                } else { enqueue(due: sampleClock + Int64(offset) + delay, status: 0x90 | ch, note: UInt8(n), vel: vel, pattern: false) }
                count += 1
            }
            slot[0] = Int32(count)
            return
        }
        if geniusEnabled && geniusHasTable {
            _ = geniusTransform(status, UInt8(pressed), d2, offset: offset, sampleTime: sampleTime, fromUI: fromUI)
            return
        }
        if scaleLockEnabled && geniusHasTable {
            if isOff {
                let n = pressedToSounding[raw] >= 0 ? Int(pressedToSounding[raw]) : pressed
                pressedToSounding[raw] = -1
                handleMIDI(0x80 | ch, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI)
            } else {
                let n = max(0, min(127, pressed + Int(table[(pressed % 12) * Self.geniusStride + 16])))
                pressedToSounding[raw] = Int16(n)
                handleMIDI(0x90 | ch, UInt8(n), d2, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI)
            }
            return
        }
        handleMIDI(isOff ? 0x80 | ch : 0x90 | ch, UInt8(pressed), isOff ? 0 : d2, offset: offset, sampleTime: sampleTime,
                   fromPattern: false, forward: true, fromUI: fromUI)
    }

    // MARK: Delayed events (strum, humanize, swing)

    private func nextRandom() -> Double {
        randomState = randomState &* 1664525 &+ 1013904223
        return Double(randomState >> 8) / 16777216.0
    }
    private func humanVel(_ v: UInt8) -> UInt8 {
        UInt8(max(1, min(127, Int((Double(v) + (nextRandom() * 2 - 1) * 14 * humanize).rounded()))))
    }
    private func humanDelay() -> Int64 { Int64(nextRandom() * 0.025 * humanize * sampleRate) }

    private func enqueue(due: Int64, status: UInt8, note: UInt8, vel: UInt8, pattern: Bool) {
        for i in 0..<1024 where !delayed[i].active {
            delayed[i] = Delayed(due: due, status: status, note: note, vel: vel, pattern: pattern, active: true)
            return
        }
    }

    private func nextDelayedOffset(done: Int, frames: Int) -> Int {
        var best = Int64.max
        for i in 0..<1024 where delayed[i].active && delayed[i].due < sampleClock + Int64(frames) { best = min(best, delayed[i].due) }
        if best == Int64.max { return frames }
        return Int(max(Int64(done), min(Int64(frames - 1), best - sampleClock)))
    }

    private func runDelayed(offset: Int, sampleTime: Float64) {
        let now = sampleClock + Int64(offset)
        inTransform = true
        for pass in 0..<2 {                      // note-offs first, then note-ons
            for i in 0..<1024 where delayed[i].active && delayed[i].due <= now {
                let d = delayed[i]
                let isOn = d.status & 0xF0 == 0x90 && d.vel > 0
                if (pass == 0) == isOn { continue }
                delayed[i].active = false
                handleMIDI(d.status, d.note, d.vel, offset: offset, sampleTime: sampleTime, fromPattern: d.pattern, forward: true)
            }
        }
        inTransform = false
    }

    /// Returns true when the event was fully handled.
    private func geniusTransform(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, offset: Int, sampleTime: Float64, fromUI: Bool) -> Bool {
        let pressed = Int(d1 & 0x7F)
        let ch = status & 0x0F
        if status & 0xF0 == 0x80 || d2 == 0 {
            let n = pressedToSounding[pressed] >= 0 ? Int(pressedToSounding[pressed]) : pressed
            pressedToSounding[pressed] = -1
            for p in 0..<128 where Int(pressedToSounding[p]) == n { return true }   // another key still holds it
            geniusEnabled = false
            handleMIDI(0x80 | ch, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI)
            geniusEnabled = true
            return true
        }
        let t = geniusTables[Int(cp_atomic_load(geniusActive))] + (pressed % 12) * Self.geniusStride
        let n = max(0, min(127, pressed + Int(t[0])))
        let now = sampleClock + Int64(offset)
        var fits = false
        for i in 0..<gNumTones where Int(gTones[i]) == n % 12 { fits = true }
        if !(gChordOn && fits && now - gChangedAt < Int64(0.18 * sampleRate)) {
            geniusChordOff(offset: offset, sampleTime: sampleTime)
            let root = Int(t[1]), nt = Int(t[2])
            gNumTones = nt
            gCount = 0
            // Pianist voicing (same as SuggestionEngine.geniusVoicing, allocation-free):
            // right hand = 3rd/7th first, then 5th, 9th, root, just below the melody; left hand = root + fifth/octave.
            func rank(_ tone: Int) -> Int {
                let r = (tone - root + 12) % 12
                if r == 3 || r == 4 || r == 10 || r == 11 { return 0 }
                if r == 6 || r == 7 || r == 8 { return 1 }
                if r == 2 || r == 5 || r == 9 { return 2 }
                return 3
            }
            for i in 0..<nt { gTones[i] = t[3 + i] }
            var low = n
            var picked = 0
            for wanted in 0...3 where picked < 3 {
                for i in 0..<nt where picked < 3 {
                    let tone = Int(t[3 + i])
                    if tone == n % 12 || rank(tone) != wanted { continue }
                    var x = n - 1
                    while x % 12 != tone { x -= 1 }
                    if x >= n - 11 { gNotes[gCount] = Int32(x); gCount += 1; low = min(low, x); picked += 1 }
                }
            }
            var b = min(low - 3, 52)
            while b % 12 != root { b -= 1 }
            if b < 28 { b += 12 }
            if b >= 24 && b < n { gNotes[gCount] = Int32(b); gCount += 1 }
            if b + 7 < low - 2 { gNotes[gCount] = Int32(b + 7); gCount += 1 }
            else if b + 12 < low - 2 { gNotes[gCount] = Int32(b + 12); gCount += 1 }
            let vel = UInt8(max(1, min(127, Int(Float(d2) * 0.62))))
            for i in 0..<gCount {
                if synthEnabled && !isMIDIEffect { noteOn(Int(gNotes[i]), velocity: vel, lane: 4) }
                sendOut(0x92, UInt8(gNotes[i]), vel, offset: offset, sampleTime: sampleTime)   // chords on MIDI channel 3
            }
            gChordOn = true; gChangedAt = now
            _ = cp_ring_push(geniusRing, 0x20000 | UInt32(root << 8) | UInt32(t[8]))
        }
        _ = cp_ring_push(geniusRing, 0x10000 | UInt32(n))
        pressedToSounding[pressed] = Int16(n)
        lastNoteAt = now
        geniusEnabled = false   // route the corrected note through the normal path
        if heldNotes[n] > 0 { handleMIDI(0x80 | ch, UInt8(n), 0, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI) }
        handleMIDI(0x90 | ch, UInt8(n), d2, offset: offset, sampleTime: sampleTime, fromPattern: false, forward: true, fromUI: fromUI)
        geniusEnabled = true
        return true
    }

    private func geniusChordOff(offset: Int, sampleTime: Float64) {
        for i in 0..<gCount {
            noteOff(Int(gNotes[i]), lane: 4)
            sendOut(0x82, UInt8(gNotes[i]), 0, offset: offset, sampleTime: sampleTime)
        }
        gCount = 0; gNumTones = 0; gChordOn = false
    }

    private func sendOut(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, offset: Int, sampleTime: Float64) {
        guard let out = midiOut else { return }
        midiBytes[0] = status; midiBytes[1] = d1; midiBytes[2] = d2
        _ = out(AUEventSampleTime(sampleTime) + AUEventSampleTime(offset), 0, 3, midiBytes)
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
        // Genre drums (kick 150→45 Hz sweep, snare noise + body, short hi-hat).
        let sr = Float(sampleRate)
        for k in 0..<3 where drumT[k] < sr * 0.6 {
            for f in start..<end {
                let time = drumT[k] / sr
                var s: Float = 0
                if k == 0 {
                    drumPhase[k] += (45 + 105 * expf(-time * 25)) / sr
                    if drumPhase[k] >= 1 { drumPhase[k] -= 1 }
                    s = sinf(drumPhase[k] * twoPi) * expf(-time * 9) * 0.9
                } else {
                    noiseSeed = noiseSeed &* 1664525 &+ 1013904223
                    let noise = Float(noiseSeed >> 9) / 4194304.0 - 1.0
                    if k == 1 {
                        drumLP[k] += 0.35 * (noise - drumLP[k])
                        drumPhase[k] += 185 / sr
                        if drumPhase[k] >= 1 { drumPhase[k] -= 1 }
                        s = (noise - drumLP[k]) * 0.55 * expf(-time * 18) + sinf(drumPhase[k] * twoPi) * 0.25 * expf(-time * 30)
                    } else {
                        drumLP[k] += 0.8 * (noise - drumLP[k])
                        s = (noise - drumLP[k]) * 0.3 * expf(-time * 70)
                    }
                }
                s *= drumVel[k] * 1.4   // the volume stage below scales everything by ≈0.35 × volume
                left[f] += s
                right?[f] += s
                drumT[k] += 1
            }
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
    case genre = 0, keyRoot, keyMinor, complexity, volume, synth, hostSync, play, progression, bpm, piano,
         arpeggio, melody, song, genius,
         oneFinger, scaleLock, strum, humanize, swing, transpose, voicing, drums
}
