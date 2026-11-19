import Foundation

/// A synthesis recipe for one of the 10 piano sounds. All engines (iPad AUv3, desktop VST3, web app)
/// use the same numbers so the instruments sound alike everywhere.
public struct PianoModel: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var emoji: String
    /// Amplitudes of harmonics 1...6.
    public var partials: [Float]
    /// String stiffness: harmonic k is played at k·f·sqrt(1 + B·k²) (makes metal/toy sounds "bell-like").
    public var inharmonicity: Float
    /// Decay time (seconds) for the lowest note; higher notes decay faster.
    public var decay: Float
    /// How fast the upper harmonics fade compared with the fundamental (0.1 = much faster).
    public var brightDecay: Float
    public var release: Float
    public var attack: Float          // seconds
    /// A detuned copy of the fundamental (cents) – honky-tonk / chorus character.
    public var detuneCents: Float
    /// Frequency-modulation for electric pianos: modulator ratio, depth and how fast the depth decays.
    public var fmRatio: Float
    public var fmIndex: Float
    public var fmDecay: Float          // seconds
    /// Hammer / pluck noise at the start of the note.
    public var click: Float
    /// 0 = velocity changes only loudness, 1 = velocity also changes brightness strongly.
    public var velocityBrightness: Float
    public var gain: Float

    public static func == (a: PianoModel, b: PianoModel) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public extension PianoModel {
    /// The 10 most common piano types in the world (generic names, no brands).
    static let all: [PianoModel] = [
        PianoModel(id: "grand", name: "Gran Coda da Concerto", emoji: "🎹",
                   partials: [1, 0.55, 0.35, 0.22, 0.12, 0.08], inharmonicity: 0.0004, decay: 7, brightDecay: 0.3,
                   release: 0.28, attack: 0.002, detuneCents: 1.5, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.05, velocityBrightness: 0.8, gain: 1.0),
        PianoModel(id: "bright", name: "Pianoforte Brillante (Pop)", emoji: "✨",
                   partials: [1, 0.72, 0.52, 0.38, 0.25, 0.16], inharmonicity: 0.0005, decay: 5, brightDecay: 0.4,
                   release: 0.22, attack: 0.0015, detuneCents: 2, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.09, velocityBrightness: 0.6, gain: 0.85),
        PianoModel(id: "upright", name: "Pianoforte Verticale", emoji: "🪵",
                   partials: [1, 0.6, 0.32, 0.26, 0.1, 0.05], inharmonicity: 0.0007, decay: 4, brightDecay: 0.25,
                   release: 0.2, attack: 0.002, detuneCents: 4, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.07, velocityBrightness: 0.7, gain: 1.0),
        PianoModel(id: "tine", name: "Piano Elettrico a Lamelle", emoji: "🔔",
                   partials: [1, 0.12, 0.05, 0, 0, 0], inharmonicity: 0, decay: 3.8, brightDecay: 0.2,
                   release: 0.3, attack: 0.002, detuneCents: 0, fmRatio: 1, fmIndex: 2.4, fmDecay: 0.35,
                   click: 0.02, velocityBrightness: 1.0, gain: 1.0),
        PianoModel(id: "reed", name: "Piano Elettrico ad Ance", emoji: "🎛️",
                   partials: [1, 0.5, 0.42, 0.16, 0.1, 0.04], inharmonicity: 0, decay: 2.6, brightDecay: 0.3,
                   release: 0.15, attack: 0.002, detuneCents: 0, fmRatio: 1, fmIndex: 1.1, fmDecay: 0.25,
                   click: 0.03, velocityBrightness: 1.0, gain: 0.9),
        PianoModel(id: "fm", name: "Piano Elettrico FM", emoji: "💎",
                   partials: [1, 0.2, 0, 0, 0, 0], inharmonicity: 0, decay: 3.2, brightDecay: 0.15,
                   release: 0.35, attack: 0.001, detuneCents: 3, fmRatio: 14, fmIndex: 1.6, fmDecay: 0.08,
                   click: 0, velocityBrightness: 1.0, gain: 1.0),
        PianoModel(id: "honky", name: "Honky-Tonk", emoji: "🤠",
                   partials: [1, 0.6, 0.4, 0.28, 0.15, 0.1], inharmonicity: 0.0005, decay: 4.2, brightDecay: 0.35,
                   release: 0.2, attack: 0.002, detuneCents: 16, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.08, velocityBrightness: 0.5, gain: 0.85),
        PianoModel(id: "harpsichord", name: "Clavicembalo", emoji: "🎼",
                   partials: [1, 0.9, 0.8, 0.7, 0.6, 0.5], inharmonicity: 0.0002, decay: 2.8, brightDecay: 0.6,
                   release: 0.07, attack: 0.001, detuneCents: 2, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.22, velocityBrightness: 0.1, gain: 0.6),
        PianoModel(id: "toy", name: "Toy Piano", emoji: "🧸",
                   partials: [1, 0, 0.6, 0, 0.4, 0], inharmonicity: 0.02, decay: 1.3, brightDecay: 0.5,
                   release: 0.1, attack: 0.001, detuneCents: 0, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.1, velocityBrightness: 0.4, gain: 0.8),
        PianoModel(id: "felt", name: "Felt Piano (Lo-Fi)", emoji: "🌙",
                   partials: [1, 0.25, 0.08, 0.03, 0, 0], inharmonicity: 0.0003, decay: 3.5, brightDecay: 0.3,
                   release: 0.5, attack: 0.009, detuneCents: 3, fmRatio: 0, fmIndex: 0, fmDecay: 0.1,
                   click: 0.015, velocityBrightness: 0.5, gain: 1.15)
    ]
}
