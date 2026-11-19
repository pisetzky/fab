// Polyphonic additive/FM piano synth implementing the 10 ChordPilot piano models (same maths as the iPad kernel).
#pragma once
#include "Engine.h"
#include <cmath>
#include <cstdint>

class PianoSynth {
public:
    static constexpr int kMaxVoices = 32;

    void prepare(double sr) { sampleRate = sr; for (auto& v : voices) v = Voice(); }
    void setModel(int index) { model = std::max(0, std::min((int) cp::pianos().size() - 1, index)); }
    void setSustain(bool s) { sustain = s; if (!s) for (auto& v : voices) if (v.active && v.pedal) { v.pedal = false; v.releasing = true; } }

    void noteOn(int note, int velocity, int lane) {
        int slot = -1, oldestIdx = 0; uint64_t oldest = UINT64_MAX;
        for (int i = 0; i < kMaxVoices; ++i) {
            auto& v = voices[i];
            if (v.active && v.note == note && v.lane == lane) { slot = i; break; }
            if (!v.active && slot < 0) slot = i;
            uint64_t sc = v.releasing ? v.age / 2 : v.age;
            if (v.active && sc < oldest) { oldest = sc; oldestIdx = i; }
        }
        if (slot < 0) slot = oldestIdx;
        const auto& m = cp::pianos()[(size_t) model];
        const float sr = (float) sampleRate;
        const float f0 = 440.0f * std::pow(2.0f, (note - 69) / 12.0f), vel = velocity / 127.0f;
        const float keyScale = std::max(0.18f, 1.0f - (note - 21) * 0.0105f);
        const float decay = std::max(0.25f, m.decay * keyScale);
        const float velBright = 1 - m.velBright + m.velBright * vel;
        Voice& old = voices[slot];
        Voice v;
        v.active = true; v.note = note; v.lane = lane; v.age = ++ageCounter;
        for (int k = 0; k < 6; ++k) {
            float h = (float) (k + 1), f = f0 * h * std::sqrt(1 + m.B * h * h);
            v.inc[k] = f / sr;
            v.amp[k] = f < sr * 0.45f ? m.partials[(size_t) k] * (k == 0 ? 1.0f : std::pow(velBright, k * 0.6f)) : 0.0f;
            v.phase[k] = old.active ? old.phase[k] : 0.0f;
        }
        v.gain = (0.12f + 0.88f * vel * vel) * m.gain * (lane == 1 ? 0.75f : 1.0f);
        v.env = 1; v.bright = 1;
        v.attack = old.active ? std::min(1.0f, old.env * old.attack) : 0.0f;
        v.attackInc = 1.0f / std::max(1.0f, m.attack * sr);
        v.decayCoef = std::exp(-1.0f / (decay * sr));
        v.brightCoef = std::exp(-1.0f / (std::max(0.05f, m.brightDecay * decay) * sr));
        v.releaseCoef = std::exp(-1.0f / (std::max(0.02f, m.release * 0.4f) * sr));
        v.fmInc = m.fmRatio > 0 ? f0 * m.fmRatio / sr : 0;
        v.fmIndex = m.fmIndex * (0.35f + 0.65f * vel);
        v.fmCoef = std::exp(-1.0f / (std::max(0.01f, m.fmDecay) * sr));
        if (m.detune > 0) { v.detInc = f0 * std::pow(2.0f, m.detune / 1200) / sr; v.detAmp = m.detune > 8 ? 0.7f : 0.35f; v.detPhase = 0.25f; }
        v.click = m.click * (0.4f + 0.6f * vel);
        v.clickCoef = std::exp(-1.0f / (0.004f * sr));
        voices[slot] = v;
    }

    void noteOff(int note, int lane) {
        for (auto& v : voices)
            if (v.active && v.note == note && v.lane == lane && !v.releasing) {
                if (sustain && lane == 0) v.pedal = true; else v.releasing = true;
            }
    }

    /// Simple synthesised drums: 0 kick, 1 snare, 2 hi-hat.
    void drum(int kind, int velocity) {
        auto& d = drums[(size_t) kind];
        d.active = true; d.t = 0; d.vel = velocity / 127.0f; d.phase = 0;
    }

    void allNotesOff() { for (auto& v : voices) if (v.active) { v.releasing = true; v.pedal = false; } }

    /// Adds into L/R from sample `start` to `end`.
    void render(float* L, float* R, int start, int end) {
        constexpr float twoPi = 6.28318530718f;
        for (auto& v : voices) {
            if (!v.active) continue;
            float pan = 0.5f + (v.note - 60) * 0.008f;
            float gl = std::cos(pan * 1.5707963f), gr = std::sin(pan * 1.5707963f);
            for (int f = start; f < end; ++f) {
                if (v.attack < 1) v.attack = std::min(1.0f, v.attack + v.attackInc);
                v.env *= v.releasing ? v.releaseCoef : v.decayCoef;
                v.bright *= v.brightCoef;
                float b = v.bright, fm = 0;
                if (v.fmInc > 0) { fm = v.fmIndex * std::sin(v.fmPhase * twoPi); v.fmIndex *= v.fmCoef; v.fmPhase += v.fmInc; v.fmPhase -= std::floor(v.fmPhase); }
                float s = v.amp[0] * std::sin(v.phase[0] * twoPi + fm);
                float bp = b;
                for (int k = 1; k < 6; ++k) { if (v.amp[k] > 0) s += v.amp[k] * bp * std::sin(v.phase[k] * twoPi); if (k % 2 == 1) bp *= b; }
                if (v.detAmp > 0) { s += v.detAmp * v.amp[0] * std::sin(v.detPhase * twoPi); v.detPhase += v.detInc; if (v.detPhase >= 1) v.detPhase -= 1; }
                if (v.click > 0.0001f) { seed = seed * 1664525u + 1013904223u; s += v.click * ((float) (seed >> 9) / 4194304.0f - 1.0f); v.click *= v.clickCoef; }
                float out = s * v.gain * v.attack * v.env * 0.6f * 0.35f;
                L[f] += out * gl; R[f] += out * gr;
                for (int k = 0; k < 6; ++k) { v.phase[k] += v.inc[k]; if (v.phase[k] >= 1) v.phase[k] -= 1; }
            }
            if ((v.releasing && v.env < 0.0005f) || (!v.releasing && v.env < 0.0003f)) v.active = false;
        }
        const float sr = (float) sampleRate;
        for (int kind = 0; kind < 3; ++kind) {
            auto& d = drums[(size_t) kind];
            if (!d.active) continue;
            for (int f = start; f < end; ++f) {
                float time = d.t / sr, s = 0;
                if (kind == 0) {             // kick: pitch sweep 150 → 45 Hz
                    float freq = 45.0f + 105.0f * std::exp(-time * 25.0f);
                    d.phase += freq / sr; if (d.phase >= 1) d.phase -= 1;
                    s = std::sin(d.phase * twoPi) * std::exp(-time * 9.0f) * 0.9f;
                } else {
                    seed = seed * 1664525u + 1013904223u;
                    float noise = (float) (seed >> 9) / 4194304.0f - 1.0f;
                    if (kind == 1) {          // snare: band-ish noise + 185 Hz body
                        d.lp += 0.35f * (noise - d.lp);
                        d.phase += 185.0f / sr; if (d.phase >= 1) d.phase -= 1;
                        s = ((noise - d.lp) * 0.55f * std::exp(-time * 18.0f)) + std::sin(d.phase * twoPi) * 0.25f * std::exp(-time * 30.0f);
                    } else {                  // hi-hat: high-passed noise, very short
                        d.lp += 0.8f * (noise - d.lp);
                        s = (noise - d.lp) * 0.3f * std::exp(-time * 70.0f);
                    }
                }
                s *= d.vel * 0.5f;
                L[f] += s; R[f] += s;
                d.t += 1;
            }
            if (d.t > sr * 0.6f) d.active = false;
        }
    }

private:
    struct Voice {
        bool active = false, releasing = false, pedal = false; int note = -1, lane = 0; uint64_t age = 0;
        float phase[6] {}, inc[6] {}, amp[6] {};
        float gain = 0, env = 0, bright = 1, attack = 0, attackInc = 0.01f, decayCoef = 0.9999f, brightCoef = 0.999f, releaseCoef = 0.999f;
        float fmPhase = 0, fmInc = 0, fmIndex = 0, fmCoef = 0.999f, detPhase = 0, detInc = 0, detAmp = 0, click = 0, clickCoef = 0.99f;
    };
    Voice voices[kMaxVoices];
    struct Drum { bool active = false; float t = 0, vel = 0, phase = 0, lp = 0; };
    std::array<Drum, 3> drums {};
    double sampleRate = 44100;
    int model = 0;
    bool sustain = false;
    uint64_t ageCounter = 0;
    uint32_t seed = 22222;
};
