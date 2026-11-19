import AVFoundation
import AudioToolbox
import Combine

/// Hosts the ChordPilot Audio Unit inside the standalone app.
/// Uses whatever audio output iOS has selected (speaker, headphones, AirPlay, Bluetooth, USB / Lightning
/// audio interfaces) and follows route changes automatically.
@MainActor
final class AudioHost: ObservableObject {

    @Published private(set) var outputName = ""
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    let engine = AVAudioEngine()
    let midi = MIDIManager()
    private(set) var audioUnit: ChordPilotAudioUnit?
    private var avUnit: AVAudioUnit?
    private var observers: [NSObjectProtocol] = []

    /// In-app registration uses its own subtype so it never clashes with the system-registered extension.
    private static let appComponent = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice, componentSubType: ChordPilotComponent.fourCC("chpa"),
        componentManufacturer: ChordPilotComponent.manufacturer, componentFlags: 0, componentFlagsMask: 0)

    private var started = false

    func start(onReady: @escaping (ChordPilotAudioUnit) -> Void) {
        guard !started else { return }
        started = true
        configureSession()
        AUAudioUnit.registerSubclass(ChordPilotAudioUnit.self, as: Self.appComponent,
                                     name: "Fab Audio: ChordPilot", version: 0x10000)
        AVAudioUnit.instantiate(with: Self.appComponent, options: []) { [weak self] unit, error in
            Task { @MainActor in
                guard let self, let unit, let au = unit.auAudioUnit as? ChordPilotAudioUnit else {
                    self?.errorMessage = error?.localizedDescription ?? "Impossibile avviare il motore audio"
                    return
                }
                self.avUnit = unit
                self.audioUnit = au
                // External MIDI is not echoed back (a digital piano would play twice).
                au.kernel.midiThru = false
                let midi = self.midi
                au.midiOutputEventBlock = { _, _, length, bytes in
                    midi.send(bytes, length: length)
                    return noErr
                }
                self.engine.attach(unit)
                self.connectGraph()
                self.startEngine()
                self.wireMIDIInput()
                self.observeChanges()
                onReady(au)
            }
        }
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP])
            try s.setPreferredIOBufferDuration(0.005)   // low latency for live playing
            try s.setActive(true)
        } catch {
            errorMessage = "Audio: \(error.localizedDescription)"
        }
        updateOutputName()
    }

    private func connectGraph() {
        guard let unit = avUnit else { return }
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sr > 0 ? sr : 48000, channels: 2)
        engine.disconnectNodeOutput(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
    }

    private func startEngine() {
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            errorMessage = nil
        } catch {
            isRunning = false
            errorMessage = "Audio: \(error.localizedDescription)"
        }
    }

    private func wireMIDIInput() {
        guard let au = audioUnit else { return }
        let schedule = au.scheduleMIDIEventBlock
        midi.onMessage = { status, d1, d2 in
            var bytes: (UInt8, UInt8, UInt8) = (status, d1, d2)
            let type = status & 0xF0
            let len = (type == 0xC0 || type == 0xD0) ? 2 : 3
            withUnsafeBytes(of: &bytes) { raw in
                if let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    schedule?(AUEventSampleTimeImmediate, 0, len, base)
                }
            }
        }
    }

    private func observeChanges() {
        let nc = NotificationCenter.default
        // New headphones, USB interface, AirPlay...: the engine reconfigures itself, we restart it.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.connectGraph()
                self?.startEngine()
                self?.wireMIDIInput()
                self?.updateOutputName()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateOutputName() }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.startEngine()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.configureSession()
                self?.connectGraph()
                self?.startEngine()
            }
        })
    }

    private func updateOutputName() {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        outputName = outs.map { $0.portName }.joined(separator: " + ")
    }
}
