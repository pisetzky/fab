import Foundation

/// Standard MIDI file (type 1) of a genre-player loop: track 1 accompaniment (ch 1), track 2 melody (ch 2).
public enum MidiExport {
    public static func data(pattern: GenrePattern, bpm: Double, loops: Int = 4) -> Data {
        let ppq = 480, perStep = ppq / 4
        func vlq(_ value: Int) -> [UInt8] {
            var v = value, bytes = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 { bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0); v >>= 7 }
            return bytes
        }
        func track(lane: UInt8, channel: UInt8, tempo: Bool) -> [UInt8] {
            var ev: [(tick: Int, status: UInt8, note: UInt8, vel: UInt8)] = []
            for l in 0..<loops {
                for e in pattern.events where e.lane == lane {
                    var step = e.step + l * pattern.totalSteps
                    if e.velocity == 0 && e.step == 0 { step = (l + 1) * pattern.totalSteps }
                    ev.append((step * perStep, (e.velocity > 0 ? 0x90 : 0x80) | channel, e.note, e.velocity))
                }
            }
            ev.sort { $0.tick != $1.tick ? $0.tick < $1.tick : ($0.status & 0xF0) < ($1.status & 0xF0) }
            var out: [UInt8] = []
            if tempo {
                let us = Int((60_000_000 / bpm).rounded())
                out += [0, 0xFF, 0x51, 3, UInt8((us >> 16) & 255), UInt8((us >> 8) & 255), UInt8(us & 255)]
            }
            var t = 0
            for e in ev { out += vlq(e.tick - t) + [e.status, e.note, e.vel]; t = e.tick }
            out += [0, 0xFF, 0x2F, 0]
            let n = out.count
            return Array("MTrk".utf8) + [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)] + out
        }
        let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, 2, UInt8(ppq >> 8), UInt8(ppq & 255)]
        return Data(header + track(lane: 0, channel: 0, tempo: true) + track(lane: 1, channel: 1, tempo: false))
    }
}
