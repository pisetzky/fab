import SwiftUI
import CoreAudioKit

@main
struct ChordPilotApp: App {
    @StateObject private var host = AudioHost()
    @StateObject private var controller = ChordPilotController()

    var body: some Scene {
        WindowGroup {
            ChordPilotView(controller: controller, trailingToolbar: AnyView(MIDIStatusButton(host: host, midi: host.midi)))
                .onAppear {
                    host.start { au in controller.attach(au) }
                }
                .onReceive(host.midi.$inputNames.combineLatest(host.$outputName)) { inputs, output in
                    let midiText = inputs.isEmpty ? "Nessun MIDI" : "MIDI: " + inputs.joined(separator: ", ")
                    controller.connectionStatus = "🔊 \(output)  ·  🎹 \(midiText)"
                }
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Toolbar button showing what is connected, with Bluetooth MIDI pairing.
struct MIDIStatusButton: View {
    @ObservedObject var host: AudioHost
    @ObservedObject var midi: MIDIManager
    @State private var showPanel = false
    @State private var showBluetooth = false

    var body: some View {
        Button { showPanel = true } label: {
            Image(systemName: midi.inputNames.isEmpty ? "cable.connector" : "cable.connector.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 34)
                .background(Circle().fill(Color.white.opacity(midi.inputNames.isEmpty ? 0.08 : 0.2)))
        }
        .accessibilityLabel("Connessioni MIDI e audio")
        .popover(isPresented: $showPanel) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connessioni automatiche").font(.headline)
                Text("ChordPilot si collega da solo a ogni tastiera MIDI (USB, Bluetooth, Wi-Fi, app virtuali). Non serve impostare nulla.")
                    .font(.footnote).foregroundColor(.secondary)
                Group {
                    Label("Uscita audio: \(host.outputName)", systemImage: "speaker.wave.2.fill")
                    Label("Ingressi MIDI", systemImage: "pianokeys")
                    if midi.inputNames.isEmpty { Text("   Nessuno (collega una tastiera)").foregroundColor(.secondary) }
                    ForEach(midi.inputNames, id: \.self) { Text("   • \($0)") }
                    Label("Uscite MIDI", systemImage: "arrow.up.right.circle")
                    Text("   • ChordPilot Out (virtuale, per DAW e app)")
                    ForEach(midi.outputNames, id: \.self) { Text("   • \($0)") }
                }
                .font(.subheadline)
                Toggle("Invia anche alle uscite MIDI hardware", isOn: $midi.sendToHardware)
                Button { showBluetooth = true } label: {
                    Label("Abbina tastiera MIDI Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                if let err = host.errorMessage { Text(err).foregroundColor(.red).font(.footnote) }
            }
            .padding(20)
            .frame(width: 380)
            .sheet(isPresented: $showBluetooth) { BluetoothMIDIView() }
        }
    }
}

/// Apple's standard Bluetooth-MIDI pairing panel.
struct BluetoothMIDIView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CABTMIDICentralViewController()
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in
            vc.dismiss(animated: true)
        })
        return UINavigationController(rootViewController: vc)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
