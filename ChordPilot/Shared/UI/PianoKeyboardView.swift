import UIKit
import SwiftUI
import ChordPilotCore

/// Multi-touch piano keyboard that glows on the suggested next notes.
final class PianoKeyboardUIView: UIView {

    var lowestNote = 48 { didSet { if oldValue != lowestNote { releaseAll(); setNeedsDisplay() } } }
    var octaves = 3 { didSet { if oldValue != octaves { releaseAll(); setNeedsDisplay() } } }
    var held: Set<Int> = [] { didSet { if oldValue != held { setNeedsDisplay() } } }
    var patternNotes: Set<Int> = [] { didSet { if oldValue != patternNotes { setNeedsDisplay() } } }
    var melodyNotes: Set<Int> = [] { didSet { if oldValue != melodyNotes { setNeedsDisplay() } } }
    var geniusNext: [Int: String] = [:] { didSet { if oldValue != geniusNext { setNeedsDisplay() } } }
    var splitNote: Int? = nil { didSet { if oldValue != splitNote { setNeedsDisplay() } } }
    var hideHints = false { didSet { if oldValue != hideHints { setNeedsDisplay() } } }
    var highlights: [Int: KeyHighlight] = [:] { didSet { if oldValue != highlights { setNeedsDisplay() } } }
    var accent: UIColor = .systemPink { didSet { setNeedsDisplay() } }
    var showScale = true { didSet { setNeedsDisplay() } }
    var labelFor: ((Int) -> String)? { didSet { setNeedsDisplay() } }

    var onNoteDown: ((Int, Int) -> Void)?
    var onNoteUp: ((Int) -> Void)?

    private var touchNotes: [UITouch: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var highestNote: Int { lowestNote + octaves * 12 }   // inclusive top C

    private static let blackPCs: Set<Int> = [1, 3, 6, 8, 10]
    private func isBlack(_ n: Int) -> Bool { Self.blackPCs.contains(mod12(n)) }

    private var whiteNotes: [Int] { (lowestNote...highestNote).filter { !isBlack($0) } }

    private func frame(for note: Int) -> CGRect {
        let whites = whiteNotes
        let w = bounds.width / CGFloat(max(1, whites.count))
        if !isBlack(note) {
            let i = whites.firstIndex(of: note) ?? 0
            return CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
        }
        let leftWhite = whites.firstIndex(of: note - 1) ?? 0
        let bw = w * 0.62
        // Slight offsets like a real keyboard.
        let shift: CGFloat
        switch mod12(note) {
        case 1, 6: shift = -0.08
        case 3, 10: shift = 0.08
        default: shift = 0
        }
        let x = CGFloat(leftWhite + 1) * w - bw / 2 + shift * bw
        return CGRect(x: x, y: 0, width: bw, height: bounds.height * 0.62)
    }

    private func note(at p: CGPoint) -> (Int, Int)? {
        guard bounds.contains(p) else { return nil }
        for n in lowestNote...highestNote where isBlack(n) {
            let f = frame(for: n)
            if f.contains(p) { return (n, velocity(p.y, height: f.height)) }
        }
        for n in whiteNotes {
            let f = frame(for: n)
            if f.contains(p) { return (n, velocity(p.y, height: f.height)) }
        }
        return nil
    }

    /// Touching nearer the front of the key plays louder.
    private func velocity(_ y: CGFloat, height: CGFloat) -> Int {
        let t = max(0, min(1, y / max(1, height)))
        return Int(45 + t * 82)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let corner: CGFloat = 6
        for n in whiteNotes { drawKey(n, ctx: ctx, black: false, corner: corner) }
        for n in lowestNote...highestNote where isBlack(n) { drawKey(n, ctx: ctx, black: true, corner: corner * 0.7) }
    }

    private func color(for h: KeyHighlight) -> UIColor {
        switch h.role {
        case .primary: return accent
        case .alternative: return Aurora.uiViolet
        case .melody: return Aurora.uiCyan
        case .signature: return accent
        case .scale: return UIColor.white
        }
    }

    private func drawKey(_ n: Int, ctx: CGContext, black: Bool, corner: CGFloat) {
        let f = frame(for: n).insetBy(dx: black ? 0 : 1, dy: 0)
        let path = UIBezierPath(roundedRect: f, byRoundingCorners: [.bottomLeft, .bottomRight],
                                cornerRadii: CGSize(width: corner, height: corner))
        let isHeld = held.contains(n)
        let isPattern = patternNotes.contains(n)
        let h = highlights[n]

        // Base
        var base: UIColor = black ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.96, alpha: 1)
        if isHeld { base = black ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.78, alpha: 1) }
        base.setFill()
        path.fill()

        // Two hands: left-hand zone tinted, gold line at the split.
        if let split = splitNote, n < split, !black {
            UIColor(red: 0.85, green: 0.94, blue: 1.0, alpha: 1).setFill(); path.fill()
        }
        // Glow for suggestions (hidden in easy mode, where only the gold keys guide the player)
        if !hideHints, let h = h, h.role >= .melody || (showScale && h.role >= .scale) {
            ctx.saveGState()
            path.addClip()
            let c = color(for: h)
            let alpha: CGFloat
            switch h.role {
            case .primary: alpha = 0.95
            case .alternative: alpha = h.rank == 1 ? 0.6 : 0.42
            case .melody: alpha = 0.55
            case .signature, .scale: alpha = 0
            }
            if alpha > 0 {
                let colors = [c.withAlphaComponent(alpha * 0.25).cgColor, c.withAlphaComponent(alpha).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: f.midX, y: f.minY),
                                           end: CGPoint(x: f.midX, y: f.maxY), options: [])
                }
            }
            ctx.restoreGState()

            // Small markers for scale / genre colour notes.
            if h.role == .scale || h.role == .signature {
                let d: CGFloat = min(f.width * 0.28, 9)
                let dot = CGRect(x: f.midX - d / 2, y: f.maxY - d - 8, width: d, height: d)
                let dotColor: UIColor = h.role == .signature ? accent : (black ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.62, alpha: 1))
                dotColor.withAlphaComponent(h.role == .signature ? 0.95 : 0.8).setFill()
                if h.role == .signature {
                    let dp = UIBezierPath()
                    dp.move(to: CGPoint(x: dot.midX, y: dot.minY)); dp.addLine(to: CGPoint(x: dot.maxX, y: dot.midY))
                    dp.addLine(to: CGPoint(x: dot.midX, y: dot.maxY)); dp.addLine(to: CGPoint(x: dot.minX, y: dot.midY))
                    dp.close(); dp.fill()
                } else {
                    UIBezierPath(ovalIn: dot).fill()
                }
            }
        }

        // Genre player notes: green bar on top.
        if isPattern {
            Aurora.uiMagenta.withAlphaComponent(0.9).setFill()
            UIBezierPath(roundedRect: CGRect(x: f.minX + 3, y: 4, width: f.width - 6, height: 6), cornerRadius: 3).fill()
        }

        // Genre player melody: pink bar.
        if melodyNotes.contains(n) {
            UIColor(hex: 0xFF6FB5).setFill()
            UIBezierPath(roundedRect: CGRect(x: f.minX + 3, y: 13, width: f.width - 6, height: 6), cornerRadius: 3).fill()
        }

        // Pianist mode: gold outline + chord the key will produce.
        if let chordLabel = geniusNext[n] {
            let gold = UIColor(hex: 0xFFC233)
            ctx.saveGState(); gold.setStroke(); path.lineWidth = 3; path.stroke(); ctx.restoreGState()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: UIColor(hex: 0x3A2400)]
            let size = (chordLabel as NSString).size(withAttributes: attrs)
            let tag = CGRect(x: f.midX - size.width / 2 - 4, y: black ? 12 : f.maxY - 64, width: size.width + 8, height: size.height + 4)
            gold.setFill(); UIBezierPath(roundedRect: tag, cornerRadius: 5).fill()
            (chordLabel as NSString).draw(at: CGPoint(x: tag.minX + 4, y: tag.minY + 2), withAttributes: attrs)
        }
        if let split = splitNote, n == split {
            UIColor(hex: 0xFFC233).setFill(); UIBezierPath(rect: CGRect(x: f.minX, y: 0, width: 3, height: f.height)).fill()
        }

        // Held notes: bright outline.
        if isHeld {
            ctx.saveGState()
            UIColor(hex: 0x19D3C5).setStroke()
            path.lineWidth = 3
            path.stroke()
            ctx.restoreGState()
        }

        // Outline
        UIColor(white: 0, alpha: black ? 0.6 : 0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Labels: every C, plus suggested primary keys.
        let showLabel = mod12(n) == 0 || h?.role == .primary || isHeld
        if showLabel, let label = labelFor?(n) {
            let textColor: UIColor = (h?.role == .primary && !black) ? .white : (black ? .white : UIColor(white: 0.25, alpha: 1))
            let font = UIFont.systemFont(ofSize: min(13, f.width * 0.32), weight: h?.role == .primary ? .bold : .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let size = (label as NSString).size(withAttributes: attrs)
            let y = black ? f.maxY - size.height - 22 : f.maxY - size.height - 22
            (label as NSString).draw(at: CGPoint(x: f.midX - size.width / 2, y: y), withAttributes: attrs)
        }
    }

    // MARK: Touches (multi-touch + glissando)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if case let (n, v)? = note(at: t.location(in: self)) {
                touchNotes[t] = n
                onNoteDown?(n, v)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let current = touchNotes[t]
            let hit = note(at: t.location(in: self))
            if hit?.0 != current {
                if let c = current, !touchNotes.contains(where: { $0.key != t && $0.value == c }) { onNoteUp?(c) }
                touchNotes[t] = hit?.0
                if case let (n, v)? = hit { onNoteDown?(n, v) }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        for t in touches {
            if let n = touchNotes.removeValue(forKey: t),
               !touchNotes.values.contains(n) { onNoteUp?(n) }
        }
    }

    private func releaseAll() {
        for n in Set(touchNotes.values) { onNoteUp?(n) }
        touchNotes.removeAll()
    }
}

/// SwiftUI wrapper.
struct PianoKeyboard: UIViewRepresentable {
    @ObservedObject var controller: ChordPilotController
    var accent: UIColor

    func makeUIView(context: Context) -> PianoKeyboardUIView {
        let v = PianoKeyboardUIView()
        v.onNoteDown = { n, vel in controller.noteDown(n, velocity: vel) }
        v.onNoteUp = { n in controller.noteUp(n) }
        update(v)
        return v
    }

    func updateUIView(_ v: PianoKeyboardUIView, context: Context) { update(v) }

    private func update(_ v: PianoKeyboardUIView) {
        v.lowestNote = controller.lowestNote
        v.octaves = controller.octaves
        v.held = controller.held
        v.patternNotes = controller.patternNotes
        v.melodyNotes = controller.melodyNotes
        v.geniusNext = controller.genius ? controller.geniusNext : [:]
        v.splitNote = controller.twoHands ? Int(controller.proValue(.split)) : nil
        v.hideHints = controller.easyMode
        v.highlights = controller.result.highlights
        v.accent = accent
        v.showScale = controller.showScaleHints
        let c = controller
        let flats = controller.result.key.prefersFlats
        v.labelFor = { n in
            let name = c.noteName(n, flats: flats)
            return mod12(n) == 0 ? name + String(n / 12 - 1) : name
        }
    }
}
