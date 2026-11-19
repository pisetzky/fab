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

/// The complete ChordPilot interface, used both by the standalone app and inside DAWs (AUv3 view).
public struct ChordPilotView: View {
    @ObservedObject var controller: ChordPilotController
    var trailingToolbar: AnyView?

    public init(controller: ChordPilotController, trailingToolbar: AnyView? = nil) {
        self.controller = controller
        self.trailingToolbar = trailingToolbar
    }

    private var accent: Color { Color(hex: controller.genre.colorHex) }

    public var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 520
            VStack(spacing: compact ? 6 : 10) {
                header(compact: compact)
                statusRow
                suggestionStrip(compact: compact)
                if controller.isPlaying || !compact { progressionStrip }
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

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B0D17), Color(hex: 0x141428)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.28), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x33C4FF, alpha: 0.12), .clear], center: .bottomTrailing,
                           startRadius: 10, endRadius: 600)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: controller.genre.id)
    }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pianokeys.inverse")
                    .font(.system(size: compact ? 18 : 22, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [accent, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
                if !compact {
                    Text("ChordPilot").font(.system(size: 22, weight: .heavy, design: .rounded))
                }
            }

            genreMenu
            keyMenu

            Picker("Complessità", selection: Binding(get: { controller.complexity },
                                                    set: { controller.setComplexity($0) })) {
                ForEach(ChordComplexity.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer(minLength: 4)

            playerControls
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
            pill(icon: nil, text: "\(controller.genre.emoji) \(controller.genre.name)", tint: accent, bold: true)
        }
        .accessibilityLabel("Genere musicale")
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
                    .background(Capsule().fill(controller.isPlaying ? Color.green.opacity(0.85) : accent.opacity(0.85)))
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
            legendItem(Color(red: 0.35, green: 0.85, blue: 1), "Alternative")
            legendItem(Color(red: 1, green: 0.78, blue: 0.25), "Melodia")
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
        let tint = isBest ? accent : Color(red: 0.35, green: 0.85, blue: 1)
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
                    .background(Capsule().fill(active ? Color.green.opacity(0.85) : Color.white.opacity(0.07)))
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
            PianoKeyboard(controller: controller, accent: UIColor(hex: controller.genre.colorHex))
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
