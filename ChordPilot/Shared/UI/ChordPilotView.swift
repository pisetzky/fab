import SwiftUI
import ChordPilotCore

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Northern-lights colour palette used across the whole interface.
public enum Aurora {
    public static let night = Color(hex: 0x050B1A)
    public static let deep = Color(hex: 0x0B1736)
    public static let green = Color(hex: 0x3DFFB0)
    public static let teal = Color(hex: 0x19D3C5)
    public static let cyan = Color(hex: 0x5CD6FF)
    public static let violet = Color(hex: 0x8E6CFF)
    public static let magenta = Color(hex: 0xE05BFF)
    public static let pink = Color(hex: 0xFF6FB5)   // genre-player melody

    static let uiGreen = UIColor(hex: 0x3DFFB0)
    static let uiViolet = UIColor(hex: 0x8E6CFF)
    static let uiCyan = UIColor(hex: 0x5CD6FF)
    static let uiMagenta = UIColor(hex: 0xE05BFF)
}

/// Slowly drifting aurora curtains behind the interface.
struct AuroraBackground: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Aurora.night, Aurora.deep, Color(hex: 0x071026)], startPoint: .top, endPoint: .bottom)
            band(Aurora.green, x: drift ? -0.25 : 0.1, y: -0.32, w: 1.5, h: 0.32, angle: -12, opacity: 0.45)
            band(Aurora.teal, x: drift ? 0.3 : -0.05, y: -0.18, w: 1.2, h: 0.24, angle: 8, opacity: 0.35)
            band(Aurora.violet, x: drift ? 0.05 : 0.4, y: -0.4, w: 1.1, h: 0.26, angle: -4, opacity: 0.4)
            band(Aurora.magenta, x: drift ? 0.45 : 0.2, y: -0.46, w: 0.8, h: 0.16, angle: 14, opacity: 0.25)
            // Stars
            Canvas { ctx, size in
                var seed: UInt64 = 42
                for _ in 0..<70 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed >> 40) / CGFloat(1 << 24) * size.width
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let y = CGFloat(seed >> 40) / CGFloat(1 << 24) * size.height * 0.6
                    let r = CGFloat((seed >> 20) & 3) * 0.4 + 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.55)))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift.toggle() } }
    }

    private func band(_ c: Color, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: Double, opacity: Double) -> some View {
        GeometryReader { geo in
            Ellipse()
                .fill(LinearGradient(colors: [c.opacity(0), c.opacity(opacity), c.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * w, height: geo.size.height * h)
                .rotationEffect(.degrees(angle))
                .blur(radius: 50)
                .position(x: geo.size.width * (0.5 + x), y: geo.size.height * (0.5 + y))
        }
    }
}

/// The complete ChordPilot interface, used both by the standalone app and inside DAWs (AUv3 view).
/// Pro options sheet: extras found in Scaler, Captain Chords and InstaChord/Cthulhu. All off by default.
struct ProOptionsView: View {
    @ObservedObject var controller: ChordPilotController
    @Environment(\.dismiss) private var dismiss
    @State private var midiURL: URL?

    private func toggle(_ a: ParamAddress) -> Binding<Bool> {
        Binding(get: { controller.proValue(a) > 0.5 }, set: { controller.setPro(a, $0 ? 1 : 0) })
    }
    private func value(_ a: ParamAddress) -> Binding<Double> {
        Binding(get: { controller.proValue(a) }, set: { controller.setPro(a, $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Funzioni prese dai migliori plug-in simili (Scaler, Captain Chords, InstaChord/Cthulhu).")) {
                    Toggle("🖐 Accordi con un dito", isOn: toggle(.oneFinger))
                    Toggle("🔒 Blocca scala", isOn: toggle(.scaleLock))
                    Toggle("🥁 Batteria del genere (Genre Player)", isOn: toggle(.drums))
                }
                Section("Suono") {
                    VStack(alignment: .leading) {
                        Text("🎸 Strum accordi: \(Int(controller.proValue(.strum))) ms")
                        Slider(value: value(.strum), in: 0...120, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("🤲 Humanize: \(Int(controller.proValue(.humanize)))%")
                        Slider(value: value(.humanize), in: 0...100, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("💃 Swing Genre Player: \(Int(controller.proValue(.swing)))%")
                        Slider(value: value(.swing), in: 0...60, step: 5)
                    }
                    Stepper("↕︎ Trasponi tastiera: \(Int(controller.proValue(.transpose)))", value: value(.transpose), in: -12...12, step: 1)
                    Picker("Voicing", selection: Binding(get: { Int(controller.proValue(.voicing)) }, set: { controller.setPro(.voicing, Double($0)) })) {
                        ForEach(Array(SuggestionEngine.voicingStyles.enumerated()), id: \.offset) { i, v in Text(v).tag(i) }
                    }
                }
                Section(footer: Text("Traccia 1 accompagnamento, traccia 2 melodia. Condividi verso GarageBand, Logic, AUM, File…")) {
                    Button("Prepara MIDI della canzone (4 giri)") { midiURL = controller.exportMIDI() }
                    if let url = midiURL {
                        ShareLink(item: url) { Label("Condividi \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Opzioni Pro")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }
}

/// Inspiration sheet: record the track (what you play or the MIDI the plug-in receives), get 10 melodies.
struct InspirationView: View {
    @ObservedObject var controller: ChordPilotController
    @Environment(\.dismiss) private var dismiss
    @State private var shareURLs: [Int: URL] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text(controller.inspireStatus)) {
                    HStack {
                        Button("⏺ Registra 4 battute") { controller.startInspiration(bars: 4) }.buttonStyle(.borderedProminent)
                        Button("8 battute") { controller.startInspiration(bars: 8) }.buttonStyle(.bordered)
                        Button("Usa il Genre Player") { controller.inspirationFromPlayer() }.buttonStyle(.bordered)
                    }
                }
                if !controller.inspireOptions.isEmpty {
                    Section("10 melodie che seguono la traccia") {
                        ForEach(Array(controller.inspireOptions.enumerated()), id: \.offset) { i, o in
                            HStack {
                                Text("\(i + 1). \(o.name)").font(.headline)
                                Spacer()
                                Button { controller.playInspiration(i) } label: { Label("Ascolta", systemImage: "play.fill") }
                                    .buttonStyle(.bordered)
                                if let url = shareURLs[i] {
                                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                } else {
                                    Button { shareURLs[i] = controller.exportInspiration(i) } label: { Image(systemName: "doc.badge.arrow.up") }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("💡 Ispirazione")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }
}

public struct ChordPilotView: View {
    @ObservedObject var controller: ChordPilotController
    @State private var showPro = false
    @State private var showInspiration = false
    var trailingToolbar: AnyView?

    public init(controller: ChordPilotController, trailingToolbar: AnyView? = nil) {
        self.controller = controller
        self.trailingToolbar = trailingToolbar
    }

    private var accent: Color { Aurora.green }

    public var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 520
            VStack(spacing: compact ? 6 : 10) {
                header(compact: compact)
                if controller.easyMode {
                    easyBar
                } else {
                    statusRow
                    songBar
                    suggestionStrip(compact: compact)
                    if controller.isPlaying || !compact { progressionStrip }
                }
                keyboardArea
                    .frame(minHeight: 120)
            }
            .padding(.horizontal, compact ? 8 : 16)
            .padding(.vertical, compact ? 6 : 12)
            .background(background)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Background

    private var background: some View { AuroraBackground() }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pianokeys.inverse")
                    .font(.system(size: compact ? 18 : 22, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Aurora.green, Aurora.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                if !compact {
                    Text("ChordPilot").font(.system(size: 22, weight: .heavy, design: .rounded))
                }
            }

            genreMenu
            pianoMenu
            if !controller.easyMode {
                keyMenu

                Picker("Complessità", selection: Binding(get: { controller.complexity },
                                                        set: { controller.setComplexity($0) })) {
                    ForEach(ChordComplexity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            Spacer(minLength: 4)

            if !controller.easyMode { playerControls }
            Button { controller.easyMode.toggle() } label: {
                Text(controller.easyMode ? "🎛 Avanzata" : "😊 Facile").font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().stroke(Aurora.green.opacity(0.6), lineWidth: 1))
                    .foregroundColor(.white)
            }
            optionsMenu
            if let extra = trailingToolbar { extra }
        }
    }

    private var genreMenu: some View {
        Menu {
            ForEach(Genre.all) { g in
                Button { controller.setGenre(g) } label: {
                    if g == controller.genre { Label("\(g.emoji)  \(g.name)", systemImage: "checkmark") }
                    else { Text("\(g.emoji)  \(g.name)") }
                }
            }
        } label: {
            pill(icon: nil, text: "\(controller.genre.emoji) \(controller.genre.name)", tint: Aurora.green, bold: true)
        }
        .accessibilityLabel("Genere musicale")
    }

    private var pianoMenu: some View {
        Menu {
            if controller.isMIDIEffect {
                Text("Versione MIDI FX: il suono lo produce lo strumento collegato")
            }
            ForEach(PianoModel.all) { m in
                Button { controller.setPiano(m) } label: {
                    if m == controller.piano { Label("\(m.emoji)  \(m.name)", systemImage: "checkmark") }
                    else { Text("\(m.emoji)  \(m.name)") }
                }
            }
        } label: {
            pill(icon: nil, text: "\(controller.piano.emoji) \(controller.piano.name)", tint: Aurora.violet, bold: true)
        }
        .accessibilityLabel("Tipo di pianoforte")
    }

    private var keyMenu: some View {
        Menu {
            Button { controller.setKey(0) } label: {
                Label("Auto (rileva mentre suoni)", systemImage: controller.keySelection == 0 ? "checkmark" : "wand.and.stars")
            }
            Divider()
            ForEach(0..<12, id: \.self) { pc in
                Button { controller.setKey(pc + 1) } label: {
                    let name = controller.noteName(pc, flats: [1, 3, 6, 8, 10].contains(pc))
                    if controller.keySelection == pc + 1 { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Toggle("Minore", isOn: Binding(get: { controller.minorMode }, set: { controller.setMinor($0) }))
        } label: {
            let k = controller.result.key
            let name = controller.noteName(k.tonic, flats: k.prefersFlats) + (k.isMinor ? "m" : "")
            pill(icon: controller.keySelection == 0 ? "wand.and.stars" : "music.note",
                 text: name + (controller.keySelection == 0 ? " · auto" : ""), tint: .white, bold: false)
        }
        .accessibilityLabel("Tonalità")
    }

    private var playerControls: some View {
        HStack(spacing: 6) {
            Button { controller.togglePlay() } label: {
                Image(systemName: controller.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 34)
                    .background(Capsule().fill(controller.isPlaying ? Aurora.magenta.opacity(0.9) : accent.opacity(0.85)))
                    .foregroundColor(.black)
            }
            .accessibilityLabel(controller.isPlaying ? "Ferma Genre Player" : "Avvia Genre Player")
            HStack(spacing: 2) {
                Button { controller.setBPM(controller.bpm - 1) } label: { Image(systemName: "minus") }
                Text("\(Int(controller.bpm)) BPM").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 64)
                Button { controller.setBPM(controller.bpm + 1) } label: { Image(systemName: "plus") }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
    }

    private var optionsMenu: some View {
        Menu {
            if !controller.isMIDIEffect {
                Toggle("Pianoforte interno", isOn: Binding(get: { controller.synthOn }, set: { controller.setSynth($0) }))
            }
            Toggle("Sincronizza con la DAW", isOn: Binding(get: { controller.hostSync }, set: { controller.setHostSync($0) }))
            Toggle("Mostra note della scala", isOn: $controller.showScaleHints)
            Toggle("Nomi italiani (Do Re Mi)", isOn: $controller.italianNames)
            Divider()
            Picker("Progressione del Genre Player", selection: Binding(get: { controller.progressionIndex },
                                                                     set: { controller.setProgression($0) })) {
                ForEach(Array(controller.genre.progressions.enumerated()), id: \.offset) { i, p in
                    Text(p.chords.map { $0.symbol }.joined(separator: " – ")).tag(i)
                }
            }
            Picker("Ottave", selection: Binding(get: { controller.octaves }, set: { controller.setOctaves($0) })) {
                ForEach(1...6, id: \.self) { Text("\($0) ottave").tag($0) }
            }
            Divider()
            Button { controller.resetContext() } label: { Label("Azzera contesto", systemImage: "arrow.counterclockwise") }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }

    private func pill(icon: String?, text: String, tint: Color, bold: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
            Text(text).font(.system(size: 15, weight: bold ? .bold : .semibold, design: .rounded)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).opacity(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(tint.opacity(bold ? 0.22 : 0.08)))
        .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
        .foregroundColor(.white)
    }

    // MARK: Easy mode

    private var playModePicker: some View {
        Picker("Ogni tasto suona", selection: Binding(get: { controller.notesOnly }, set: { controller.setNotesOnly($0) })) {
            Text("🎹 Accordi").tag(false)
            Text("🎵 Note").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }

    private var easyBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                playModePicker
                Button { controller.newSong() } label: {
                    Label("Nuova canzone", systemImage: "dice.fill").font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(LinearGradient(colors: [Aurora.pink.opacity(0.45), Aurora.violet.opacity(0.45)], startPoint: .leading, endPoint: .trailing)))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("STAI SUONANDO").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.5))
                    Text(controller.result.currentChord.map { controller.chordName($0) } ?? "—")
                        .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(.white)
                }
            }
            Text("✨ Tocca tasti a caso: ogni nota diventa musica giusta. I tasti d'oro sono un buon prossimo passo.")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        }
    }

    // MARK: Song bar: arpeggio, melody, new song, genius mode

    private var songBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Button { controller.setArpeggio(-1) } label: { Text("Ritmo del genere") }
                    ForEach(Array(Arpeggios.all.enumerated()), id: \.offset) { i, a in
                        Button { controller.setArpeggio(i) } label: {
                            if controller.arpeggio == i { Label("\(i + 1). \(a.name)", systemImage: "checkmark") } else { Text("\(i + 1). \(a.name)") }
                        }
                    }
                } label: {
                    pill(icon: "waveform.path", text: controller.arpeggio >= 0 ? "Arpeggio: \(Arpeggios.all[controller.arpeggio].name)" : "Arpeggio: ritmo del genere",
                         tint: Aurora.teal, bold: false)
                }
                Menu {
                    Button { controller.setMelody(-1) } label: { Text("Nessuna melodia") }
                    ForEach(Array(Melodies.names.enumerated()), id: \.offset) { i, name in
                        Button { controller.setMelody(i) } label: {
                            if controller.melody == i { Label("\(i + 1). \(name)", systemImage: "checkmark") } else { Text("\(i + 1). \(name)") }
                        }
                    }
                } label: {
                    pill(icon: "music.quarternote.3", text: controller.melody >= 0 ? "Melodia \(controller.melody + 1): \(Melodies.names[controller.melody])" : "Melodia: nessuna",
                         tint: Aurora.pink, bold: false)
                }
                Button { controller.newSong() } label: {
                    Label("Nuova canzone", systemImage: "dice.fill")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(LinearGradient(colors: [Aurora.pink.opacity(0.45), Aurora.violet.opacity(0.45)],
                                                                  startPoint: .leading, endPoint: .trailing)))
                        .foregroundColor(.white)
                }
                Button { controller.setGenius(!controller.genius) } label: {
                    Label("Modalità Genio", systemImage: "brain.head.profile")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(controller.genius
                            ? AnyShapeStyle(LinearGradient(colors: [Aurora.green, Aurora.cyan], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.08))))
                        .foregroundColor(controller.genius ? Color(hex: 0x022018) : .white)
                        .shadow(color: controller.genius ? Aurora.green.opacity(0.6) : .clear, radius: 10)
                }
                .accessibilityLabel(controller.genius ? "Disattiva Modalità Genio" : "Attiva Modalità Genio")
                playModePicker
                Toggle(isOn: Binding(get: { controller.twoHands }, set: { controller.setTwoHands($0) })) {
                    Text("🙌 Due mani").font(.system(size: 14, weight: .bold))
                }
                .toggleStyle(.button)
                Button { showInspiration = true } label: {
                    Label("Ispirazione", systemImage: "lightbulb.fill")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().stroke(Color(hex: 0xFFC233).opacity(0.7), lineWidth: 1))
                        .foregroundColor(.white)
                }
                .sheet(isPresented: $showInspiration) { InspirationView(controller: controller) }
                Button { showPro = true } label: {
                    Label("Pro", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().stroke(Aurora.cyan.opacity(0.6), lineWidth: 1))
                        .foregroundColor(.white)
                }
                .sheet(isPresented: $showPro) { ProOptionsView(controller: controller) }
                if controller.song > 0 {
                    Text("Canzone #\(controller.song)").font(.system(size: 12, weight: .bold)).foregroundColor(Aurora.pink)
                }
            }
        }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("STAI SUONANDO").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.5))
                Text(controller.result.currentChord.map { controller.chordName($0) } ?? (controller.held.isEmpty ? "—" : heldNames))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)

            Image(systemName: "arrow.right").foregroundColor(accent)

            VStack(alignment: .leading, spacing: 0) {
                Text("SCALA").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.5))
                Text(controller.noteName(controller.result.key.tonic, flats: controller.result.key.prefersFlats)
                     + " " + controller.result.scale.displayName)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            legend
            if !controller.connectionStatus.isEmpty {
                Text(controller.connectionStatus).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
            }
        }
    }

    private var heldNames: String {
        controller.held.sorted().map { controller.noteName($0, flats: controller.result.key.prefersFlats) }
            .joined(separator: " ")
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(accent, "Accordo migliore")
            legendItem(Aurora.violet, "Alternative")
            legendItem(Aurora.cyan, "Melodia")
            legendItem(Aurora.pink, "Melodia Player")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.7))
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t) }
    }

    // MARK: Suggestions

    private func suggestionStrip(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(controller.result.chords) { s in
                    Button { controller.play(s) } label: { suggestionCard(s, compact: compact) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.result.chords.map { $0.id })
    }

    private func suggestionCard(_ s: ChordSuggestion, compact: Bool) -> some View {
        let isBest = s.rank == 0
        let tint = isBest ? accent : Aurora.violet
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(isBest ? "PROSSIMO" : "#\(s.rank + 1)")
                    .font(.system(size: 9, weight: .heavy)).foregroundColor(tint)
                Spacer()
                Text(s.roman).font(.system(size: 11, weight: .bold, design: .serif)).foregroundColor(.white.opacity(0.7))
            }
            Text(controller.chordName(s.chord))
                .font(.system(size: compact ? 20 : 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !compact {
                Text(s.reason).font(.system(size: 10)).foregroundColor(.white.opacity(0.55)).lineLimit(2)
                    .frame(height: 26, alignment: .topLeading)
            }
        }
        .padding(10)
        .frame(width: compact ? 110 : 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [tint.opacity(isBest ? 0.35 : 0.14), Color.white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(isBest ? 0.9 : 0.3), lineWidth: isBest ? 2 : 1))
        .shadow(color: isBest ? tint.opacity(0.5) : .clear, radius: 10)
        .accessibilityLabel("Suona \(controller.chordName(s.chord))")
    }

    // MARK: Genre player progression

    private var progressionStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "metronome").foregroundColor(.white.opacity(0.6)).font(.system(size: 12))
            Text("GENRE PLAYER").font(.system(size: 9, weight: .heavy)).foregroundColor(.white.opacity(0.5))
            ForEach(Array(controller.patternChords.enumerated()), id: \.offset) { i, c in
                let active = controller.isPlaying && i == controller.patternChordIndex % max(1, controller.patternChords.count)
                Text(controller.chordName(c))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(active ? Aurora.magenta.opacity(0.9) : Color.white.opacity(0.07)))
                    .foregroundColor(active ? .black : .white.opacity(0.8))
            }
            Spacer()
        }
        .lineLimit(1)
    }

    // MARK: Keyboard

    private var keyboardArea: some View {
        HStack(spacing: 6) {
            octaveButton("chevron.left", -1)
            PianoKeyboard(controller: controller, accent: Aurora.uiGreen)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: accent.opacity(0.25), radius: 14)
            octaveButton("chevron.right", 1)
        }
    }

    private func octaveButton(_ icon: String, _ delta: Int) -> some View {
        Button { controller.shiftOctave(delta) } label: {
            Image(systemName: icon).font(.system(size: 16, weight: .bold))
                .frame(width: 30).frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
        }
        .foregroundColor(.white)
        .accessibilityLabel(delta < 0 ? "Ottava giù" : "Ottava su")
    }
}
