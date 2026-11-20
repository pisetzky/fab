#include "PluginProcessor.h"
#include "PluginEditor.h"
#include <climits>
#include <cstring>

namespace {
juce::AudioProcessorValueTreeState::ParameterLayout makeLayout() {
    using namespace juce;
    AudioProcessorValueTreeState::ParameterLayout l;
    StringArray genreNames, pianoNames, keyNames { "Auto" }, cx { "Semplici", "Del genere", "Ricchi" };
    for (auto& g : cp::genres()) genreNames.add(g.name);
    for (auto& p : cp::pianos()) pianoNames.add(p.name);
    for (int i = 0; i < 12; ++i) keyNames.add(String(cp::kItalian[i]) + " / " + cp::kSharps[i]);
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "genre", 1 }, "Genere", genreNames, 0));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "piano", 1 }, "Pianoforte", pianoNames, 0));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "key", 1 }, "Tonalita", keyNames, 0));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "minor", 1 }, "Modo minore", false));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "complexity", 1 }, "Complessita", cx, 1));
    l.add(std::make_unique<AudioParameterFloat>(ParameterID { "volume", 1 }, "Volume", NormalisableRange<float>(0, 1), 0.8f));
#if CHORDPILOT_MIDI_FX
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "synth", 1 }, "Pianoforte interno", false));
#else
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "synth", 1 }, "Pianoforte interno", true));
#endif
    // MIDI out for external instruments: separate channels (1 accompaniment, 2 melody, 3 Genius chords) or all on one channel.
    StringArray chans { "Canali separati" }; for (int c = 1; c <= 16; ++c) chans.add("Tutto sul canale " + String(c));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "midichan", 1 }, "Uscita MIDI", chans, 0));
    // Virtual MIDI port "ChordPilot": lets any DAW (also Logic) record everything the plug-in plays on a MIDI track.
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "vport", 1 }, "Porta MIDI virtuale", false));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "sync", 1 }, "Sync DAW", true));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "play", 1 }, "Genre Player", false));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "progression", 1 }, "Progressione", 0, 5, 0));
    l.add(std::make_unique<AudioParameterFloat>(ParameterID { "bpm", 1 }, "BPM", NormalisableRange<float>(40, 220, 1), 110));
    StringArray arps { "Ritmo del genere" }, mels { "Nessuna" };
    for (size_t i = 0; i < cp::arpeggios().size(); ++i) arps.add(String((int) i + 1) + ". " + String::fromUTF8(cp::arpeggios()[i].name));
    for (size_t i = 0; i < cp::melodyNames().size(); ++i) mels.add(String((int) i + 1) + ". " + String::fromUTF8(cp::melodyNames()[i].c_str()));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "arp", 1 }, "Arpeggio", arps, 0));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "melody", 1 }, "Melodia", mels, 0));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "song", 1 }, "Canzone", 0, 9999, 0));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "genius", 1 }, "Modalita Genio", false));
    // Pro options (all off by default)
    StringArray voicings; for (auto* v : cp::kVoicingStyles) voicings.add(v);
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "onefinger", 1 }, "Accordi con un dito", false));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "scalelock", 1 }, "Blocca scala", false));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "strum", 1 }, "Strum (ms)", 0, 120, 0));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "humanize", 1 }, "Humanize (%)", 0, 100, 0));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "swing", 1 }, "Swing (%)", 0, 60, 0));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "transpose", 1 }, "Trasponi", -12, 12, 0));
    l.add(std::make_unique<AudioParameterChoice>(ParameterID { "voicing", 1 }, "Voicing", voicings, 0));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "hands", 1 }, "Due mani", false));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "notesonly", 1 }, "Solo note (Genio)", false));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "easy", 1 }, "Modalita Facile", true));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "split", 1 }, "Divisione mani", 36, 84, 60));
    return l;
}
}

ChordPilotProcessor::ChordPilotProcessor()
#if CHORDPILOT_MIDI_FX
    : AudioProcessor(BusesProperties()),
#else
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)),
#endif
      params(*this, nullptr, "ChordPilot", makeLayout()) {
    for (auto& a : held) a = 0;
    for (auto& a : patternNotes) a = 0;
    for (auto& a : melodyNotes) a = 0;
    pressedToSounding.fill(-1);
    // Standalone app: publish a virtual MIDI output called "ChordPilot" (macOS / Linux). Every DAW sees it as a
    // MIDI keyboard, so pressing REC on a MIDI track records your notes, the Genius chords and the Genre Player.
    if (juce::JUCEApplicationBase::isStandaloneApp()) {
        virtualOut = juce::MidiOutput::createNewDevice("ChordPilot");
        virtualOutPtr = virtualOut.get();
    }
    rebuildPattern();
    rebuildGeniusTable();
    startTimerHz(15);
}

ChordPilotProcessor::~ChordPilotProcessor() { stopTimer(); }

bool ChordPilotProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const {
#if CHORDPILOT_MIDI_FX
    juce::ignoreUnused(layouts);
    return true;
#endif
    auto out = layouts.getMainOutputChannelSet();
    return out == juce::AudioChannelSet::stereo() || out == juce::AudioChannelSet::mono();
}

int ChordPilotProcessor::genreIndex() const { return (int) params.getRawParameterValue("genre")->load(); }
int ChordPilotProcessor::pianoIndex() const { return (int) params.getRawParameterValue("piano")->load(); }

cp::Key ChordPilotProcessor::playerKey() const {
    int k = (int) params.getRawParameterValue("key")->load();
    bool minor = params.getRawParameterValue("minor")->load() > 0.5f;
    if (k > 0) return { k - 1, minor };
    int d = detectedKeyCode.load();
    if (d >= 0) return { d % 12, d >= 12 };
    return cp::genres()[(size_t) genreIndex()].defaultKey();
}

void ChordPilotProcessor::setCurrentProgram(int index) {
    if (auto* p = params.getParameter("genre")) p->setValueNotifyingHost(p->convertTo0to1((float) index));
}

const juce::String ChordPilotProcessor::getProgramName(int index) {
    const auto& g = cp::genres();
    return index >= 0 && index < (int) g.size() ? juce::String(g[(size_t) index].name) : juce::String();
}

// ---------------------------------------------------------------- Performance recorder
void ChordPilotProcessor::pushPerf(const juce::MidiMessage& m, int offset, int track) {
    if (track != 254 && !(m.isNoteOnOrOff() || m.isSustainPedalOn() || m.isSustainPedalOff())) return;
    int s1, n1, s2, n2;
    perfFifo.prepareToWrite(1, s1, n1, s2, n2);
    if (n1 + n2 < 1) return;   // full: drop rather than block the audio thread
    auto* raw = m.getRawData();
    const int sz = m.getRawDataSize();
    perfFifoData[(size_t) (n1 > 0 ? s1 : s2)] = { sampleClock + offset, (juce::uint8) (sz > 0 ? raw[0] : 0), (juce::uint8) (sz > 1 ? raw[1] : 0),
                                                  (juce::uint8) (sz > 2 ? raw[2] : 0), (juce::uint8) track };
    perfFifo.finishedWrite(1);
}

void ChordPilotProcessor::drainPerformance() {
    int s1, n1, s2, n2; const int ready = perfFifo.getNumReady();
    perfFifo.prepareToRead(ready, s1, n1, s2, n2);
    const juce::ScopedLock sl(perfLock);
    if (perfClearRequested.exchange(false)) { perfLog.clear(); perfStartPpq = -1.0; perfLogStart = -1; }
    auto add = [this](const PerfEvent& e) { if (e.track == 254) { perfLog.clear(); perfLogStart = e.sample; } else perfLog.push_back(e); };
    for (int i = 0; i < n1; ++i) add(perfFifoData[(size_t) (s1 + i)]);
    for (int i = 0; i < n2; ++i) add(perfFifoData[(size_t) (s2 + i)]);
    perfFifo.finishedRead(n1 + n2);
    if (perfLog.size() > 400000) perfLog.erase(perfLog.begin(), perfLog.begin() + 100000);   // keep the last ~hour
}

void ChordPilotProcessor::clearPerformance() { perfClearRequested = true; drainPerformance(); }

double ChordPilotProcessor::performanceSeconds() const {
    const juce::ScopedLock sl(perfLock);
    return perfLog.size() < 2 ? 0.0 : (double) (perfLog.back().sample - perfLog.front().sample) / perfSampleRate.load();
}

int ChordPilotProcessor::performanceNotes() const {
    const juce::ScopedLock sl(perfLock);
    int c = 0; for (auto& e : perfLog) c += ((e.status & 0xf0) == 0x90 && e.d2 > 0) ? 1 : 0;
    return c;
}

juce::File ChordPilotProcessor::writePerformanceMidi(const juce::File& dest) {
    drainPerformance();
    std::vector<PerfEvent> log; juce::int64 recStart = -1;
    { const juce::ScopedLock sl(perfLock); log = perfLog; recStart = perfLogStart; }
    if (log.empty()) return {};
    const double bpm = params.getRawParameterValue("bpm")->load(), sr = perfSampleRate.load(), tpq = 480.0;
    // A take started by the DAW's REC keeps its position on the timeline (drop the file at bar 1).
    const double startPpq = perfStartPpq.load();
    const double offsetTicks = startPpq >= 0 ? startPpq * tpq : 0.0;
    const juce::int64 t0 = (startPpq >= 0 && recStart >= 0) ? recStart : log.front().sample;
    constexpr int numTracks = 4;
    const char* names[numTracks] { "Suonato da te", "Genre Player - accordi e arpeggio", "Genre Player - melodia", "Accordi del Genio" };
    juce::MidiMessageSequence tracks[numTracks];
    bool used[numTracks] {};
    for (auto& e : log) if (e.track < numTracks) used[e.track] = true;
    for (int t = 0; t < numTracks; ++t) {
        tracks[t].addEvent(juce::MidiMessage::textMetaEvent(3, names[t]));
        if (t == 0) tracks[t].addEvent(juce::MidiMessage::tempoMetaEvent((int) (60000000.0 / bpm)));
    }
    std::array<std::array<int, 128>, numTracks> open {};
    double last = 0;
    for (auto& e : log) {
        if (e.track >= numTracks) continue;
        const double tick = offsetTicks + (double) (e.sample - t0) / sr * bpm / 60.0 * tpq;
        juce::MidiMessage m(e.status, e.d1, e.d2, tick);
        auto& o = open[e.track];
        if (m.isNoteOn()) ++o[e.d1]; else if (m.isNoteOff() && o[e.d1] > 0) --o[e.d1]; else if (m.isNoteOff()) continue;
        tracks[e.track].addEvent(m); last = tick;
    }
    for (int t = 0; t < numTracks; ++t)   // close notes still held at the end of the take
        for (int n = 0; n < 128; ++n) for (int k = 0; k < open[(size_t) t][(size_t) n]; ++k)
            tracks[t].addEvent(juce::MidiMessage::noteOff(1, n).withTimeStamp(last + tpq / 2));
    juce::MidiFile file; file.setTicksPerQuarterNote((int) tpq);
    bool tempoWritten = false;
    for (int t = 0; t < numTracks; ++t) {
        if (!used[t]) continue;   // only tracks that have notes
        if (!tempoWritten && t != 0) tracks[t].addEvent(juce::MidiMessage::tempoMetaEvent((int) (60000000.0 / bpm)));
        tempoWritten = true;
        tracks[t].sort(); tracks[t].updateMatchedPairs(); file.addTrack(tracks[t]);
    }
    dest.deleteFile();
    juce::FileOutputStream os(dest);
    if (!os.openedOk() || !file.writeTo(os)) return {};
    return dest;
}

// Runs on the message thread: rebuild the genre-player loop when a musical setting changes.
void ChordPilotProcessor::timerCallback() {
    drainPerformance();
    // Inside a DAW the virtual port is opened on request (Pro > Porta MIDI virtuale) and kept until the plug-in closes.
    if (!virtualOut && params.getRawParameterValue("vport")->load() > 0.5f) {
        virtualOut = juce::MidiOutput::createNewDevice("ChordPilot");
        virtualOutPtr = virtualOut.get();
    }
    std::array<int, 8> now { genreIndex(), (int) params.getRawParameterValue("key")->load(),
                             (int) params.getRawParameterValue("minor")->load(), (int) params.getRawParameterValue("complexity")->load(),
                             (int) params.getRawParameterValue("progression")->load(), (int) params.getRawParameterValue("arp")->load(),
                             (int) params.getRawParameterValue("melody")->load(), (int) params.getRawParameterValue("song")->load() };
    int det = detectedKeyCode.load();
    if (now[0] != lastParamState[0]) {
        // New genre: adopt its typical tempo.
        if (lastParamState[0] >= 0)
            if (auto* p = params.getParameter("bpm")) p->setValueNotifyingHost(p->convertTo0to1((float) cp::genres()[(size_t) now[0]].bpm));
    }
    // Genius mode: learn from what was played and refresh the lookup table.
    {
        int s1, n1, s2, n2; int ready = geniusFifo.getNumReady();
        geniusFifo.prepareToRead(ready, s1, n1, s2, n2);
        auto consume = [this](int v) {
            if (v & 0x10000) {
                const int note = v & 0x7f, pressed = (v >> 8) & 0x7f;
                geniusEngine.noteOn(note, 100); geniusEngine.geniusPlayed(note);
                geniusEngine.melodicCommit(pressed, note, juce::Time::getMillisecondCounterHiRes());
            }
            else if (v & 0x20000) geniusEngine.commit(cp::makeChord((v >> 8) & 0xff, v & 0xff));
        };
        for (int i = 0; i < n1; ++i) consume(geniusFifoData[(size_t) (s1 + i)]);
        for (int i = 0; i < n2; ++i) consume(geniusFifoData[(size_t) (s2 + i)]);
        geniusFifo.finishedRead(n1 + n2);
        if (n1 + n2 > 0) { geniusDirty = 1; ++geniusVersion; }
    }
    if (geniusDirty || now != lastParamState) { rebuildGeniusTable(); geniusDirty = 0; }
    if (now != lastParamState || (now[1] == 0 && det != lastDetected)) {
        lastParamState = now; lastDetected = det;
        rebuildPattern();
    }
}

void ChordPilotProcessor::rebuildPattern() {
    const auto& g = cp::genres()[(size_t) juce::jlimit(0, (int) cp::genres().size() - 1, genreIndex())];
    int prog = juce::jlimit(0, (int) g.progressions.size() - 1, (int) params.getRawParameterValue("progression")->load());
    auto p = std::make_shared<const cp::Pattern>(cp::buildPattern(g, playerKey(), prog, (int) params.getRawParameterValue("complexity")->load(),
        (int) params.getRawParameterValue("arp")->load() - 1, (int) params.getRawParameterValue("melody")->load() - 1,
        (int) params.getRawParameterValue("song")->load()));
    std::atomic_store(&pattern, p);
}

void ChordPilotProcessor::rebuildGeniusTable() {
    const auto& gs = cp::genres();
    int gi = juce::jlimit(0, (int) gs.size() - 1, genreIndex());
    if (gi != lastGeniusGenre) { geniusEngine.genre = &gs[(size_t) gi]; geniusEngine.reset(); lastGeniusGenre = gi; }
    geniusEngine.complexity = (int) params.getRawParameterValue("complexity")->load();
    int k = (int) params.getRawParameterValue("key")->load();
    bool minor = params.getRawParameterValue("minor")->load() > 0.5f;
    geniusEngine.fixedKey = k == 0 ? std::nullopt : std::optional<cp::Key>(cp::Key { k - 1, minor });
    auto table = std::make_shared<GeniusTable>();
    for (int p = 0; p < 128; ++p) {
        // Preview (no commit): the most musical next note and its chord if this key is pressed now.
        auto g = geniusEngine.genius(juce::jlimit(21, 108, p), -1, false);
        auto& e = (*table)[(size_t) p];
        e.note = (p < 21 || p > 108) ? p : g.note; e.root = g.chord.root; e.quality = g.chord.quality; e.numTones = 0;
        for (int iv : cp::qualities()[(size_t) g.chord.quality].iv) {
            int t = cp::mod12(g.chord.root + iv); bool dup = false;
            for (int j = 0; j < e.numTones; ++j) dup |= e.tones[j] == t;
            if (!dup && e.numTones < 6) e.tones[e.numTones++] = t;
        }
    }
    std::atomic_store(&geniusTable, std::shared_ptr<const GeniusTable>(table));

    // One-finger chords and scale lock use the same musical context.
    auto of = std::make_shared<OneFingerTable>();
    auto chords = cp::oneFingerTable(geniusEngine);
    for (int pc = 0; pc < 12; ++pc) {
        auto& e = (*of)[(size_t) pc]; const auto& c = chords[(size_t) pc];
        e.root = c.root; e.quality = c.quality; e.numTones = std::min(6, (int) c.tones.size());
        cp::Chord lc = geniusEngine.geniusLeft(60 + pc); e.leftRoot = lc.root; e.leftQuality = lc.quality;
        for (int i = 0; i < e.numTones; ++i) e.tones[i] = c.tones[(size_t) i];
        e.lockShift = cp::lockToScale(geniusEngine, 60 + pc) - (60 + pc);
    }
    std::atomic_store(&oneFinger, std::shared_ptr<const OneFingerTable>(of));
}

// ---- Delayed events (strum / humanize / swing) ----
void ChordPilotProcessor::enqueue(long long due, juce::uint8 st, int note, int vel, bool fromPattern) {
    for (auto& d : delayed) if (!d.active) {
        d = { due, st, (juce::uint8) note, (juce::uint8) vel, fromPattern, true };
        return;
    }
}

int ChordPilotProcessor::nextDelayedOffset(int done, int n) const {
    long long best = LLONG_MAX;
    for (auto& d : delayed) if (d.active && d.due < sampleClock + n) best = std::min(best, d.due);
    if (best == LLONG_MAX) return n;
    return (int) juce::jlimit<long long>(done, n - 1, best - sampleClock);
}

void ChordPilotProcessor::runDelayed(int offset, juce::MidiBuffer& out) {
    const long long now = sampleClock + offset;
    for (int pass = 0; pass < 2; ++pass)          // note-offs first, then note-ons
        for (auto& d : delayed) {
            if (!d.active || d.due > now) continue;
            bool isOn = (d.st & 0xF0) == 0x90 && d.vel > 0;
            if ((pass == 0) == isOn) continue;
            d.active = false;
            int ch = (d.st & 0x0F) + 1;
            auto m = isOn ? juce::MidiMessage::noteOn(ch, (int) d.note, (juce::uint8) d.vel) : juce::MidiMessage::noteOff(ch, (int) d.note);
            handleMidi(m, offset, out, d.pattern);
        }
}

int ChordPilotProcessor::humanVel(int v) {
    float h = params.getRawParameterValue("humanize")->load() / 100.0f;
    return juce::jlimit(1, 127, (int) std::round(v + (rng.nextFloat() * 2 - 1) * 14 * h));
}

long long ChordPilotProcessor::humanDelay() {
    float h = params.getRawParameterValue("humanize")->load() / 100.0f;
    return (long long) (rng.nextFloat() * 0.025 * h * sampleRate);
}

void ChordPilotProcessor::geniusChordOff(int offset, juce::MidiBuffer& out) {
    for (auto& d : delayed) if (d.active && d.st == 0x92) d.active = false;   // cancel notes of a roll still pending
    for (int i = 0; i < geniusCount; ++i) {
        synth.noteOff(geniusNotes[i], 4);
        out.addEvent(juce::MidiMessage::noteOff(3, geniusNotes[i]), offset);
        pushPerf(juce::MidiMessage::noteOff(3, geniusNotes[i]), offset, 3);
    }
    geniusCount = 0; geniusNumTones = 0; geniusChordOn = false;
}

// User / host notes. In Genius mode each key becomes the closest fitting note, harmonised by the next chord.
void ChordPilotProcessor::handleInput(const juce::MidiMessage& m, int offset, juce::MidiBuffer& out) {
    const bool isNote = m.isNoteOn() || m.isNoteOff();
    if (!isNote || m.getChannel() == 16) { handleMidi(m, offset, out, false); return; }
    const int transpose = (int) params.getRawParameterValue("transpose")->load();
    const int raw = m.getNoteNumber();
    const int pressed = juce::jlimit(0, 127, raw + transpose);

    // Two hands: left = chord with its own bass, right = melody (+ chord tones under it), like a pianist.
    if (params.getRawParameterValue("hands")->load() > 0.5f && handleTwoHands(m, raw, pressed, offset, out)) return;

    // Pro: one-finger chords — the key plays the chord of the scale built on it.
    if (params.getRawParameterValue("onefinger")->load() > 0.5f) {
        auto& slot = oneFingerHeld[(size_t) raw];
        if (m.isNoteOff()) {
            for (int i = 1; i <= slot[0]; ++i) {
                bool still = false;
                for (int k = 0; k < 128 && !still; ++k) if (k != raw) for (int j = 1; j <= oneFingerHeld[(size_t) k][0]; ++j) still |= oneFingerHeld[(size_t) k][(size_t) j] == slot[(size_t) i];
                if (!still) handleMidi(juce::MidiMessage::noteOff(m.getChannel(), slot[(size_t) i]), offset, out, false);
            }
            slot[0] = 0;
            return;
        }
        auto table = std::atomic_load(&oneFinger);
        if (table) {
            const auto& e = (*table)[(size_t) cp::mod12(pressed)];
            int notes[10];
            int style = std::max(1, (int) params.getRawParameterValue("voicing")->load());
            int cnt = std::min(9, cp::styleVoicing(e.tones, e.numTones, e.root, pressed, style, notes));
            slot[0] = cnt;
            const int strum = (int) params.getRawParameterValue("strum")->load();
            for (int i = 0; i < cnt; ++i) {
                slot[(size_t) (i + 1)] = notes[i];
                long long delay = (long long) (strum / 1000.0 * sampleRate * i) + humanDelay();
                int vel = humanVel(m.getVelocity());
                if (delay == 0) handleMidi(juce::MidiMessage::noteOn(m.getChannel(), notes[i], (juce::uint8) vel), offset, out, false);
                else enqueue(sampleClock + offset + delay, (juce::uint8) (0x90 | (m.getChannel() - 1)), notes[i], vel, false);
            }
            return;
        }
    }
    const bool genius = params.getRawParameterValue("genius")->load() > 0.5f;
    // Pro: scale lock (only when Genius mode is off).
    if (!genius && params.getRawParameterValue("scalelock")->load() > 0.5f) {
        auto table = std::atomic_load(&oneFinger);
        int n = juce::jlimit(0, 127, pressed + (table ? (*table)[(size_t) cp::mod12(pressed)].lockShift : 0));
        if (m.isNoteOn()) {
            pressedToSounding[(size_t) raw] = n;
            handleMidi(juce::MidiMessage::noteOn(m.getChannel(), n, m.getVelocity()), offset, out, false);
        } else {
            int s = pressedToSounding[(size_t) raw] >= 0 ? pressedToSounding[(size_t) raw] : n;
            pressedToSounding[(size_t) raw] = -1;
            handleMidi(juce::MidiMessage::noteOff(m.getChannel(), s), offset, out, false);
        }
        return;
    }
    if (!genius) {
        if (transpose == 0) { handleMidi(m, offset, out, false); return; }
        handleMidi(m.isNoteOn() ? juce::MidiMessage::noteOn(m.getChannel(), pressed, m.getVelocity())
                                : juce::MidiMessage::noteOff(m.getChannel(), pressed), offset, out, false);
        return;
    }
    if (m.isNoteOff()) {
        int n = pressedToSounding[(size_t) raw] >= 0 ? pressedToSounding[(size_t) raw] : pressed;
        pressedToSounding[(size_t) raw] = -1;
        for (int p = 0; p < 128; ++p) if (pressedToSounding[(size_t) p] == n) return;   // another key still holds it
        handleMidi(juce::MidiMessage::noteOff(m.getChannel(), n), offset, out, false);
        return;
    }
    auto table = std::atomic_load(&geniusTable);
    if (!table) { handleMidi(m, offset, out, false); return; }
    const auto& e = (*table)[(size_t) pressed];
    const int n = juce::jlimit(0, 127, e.note);
    const long long now = sampleClock + offset;
    bool fits = false; for (int i = 0; i < geniusNumTones; ++i) fits |= geniusTones[i] == cp::mod12(n);
    const bool notesOnly = params.getRawParameterValue("notesonly")->load() > 0.5f;
    if (notesOnly && !(geniusChordOn && fits && now - geniusChangedAt < (long long) (0.18 * sampleRate))) {
        // Single notes: the harmony moves on silently (for the next suggestions), only the melody sounds.
        geniusChordOff(offset, out);
        geniusNumTones = e.numTones; for (int i = 0; i < e.numTones; ++i) geniusTones[i] = e.tones[i];
        geniusChordOn = true; geniusChangedAt = now;
        int s1, n1, s2, n2; geniusFifo.prepareToWrite(1, s1, n1, s2, n2);
        if (n1 > 0) { geniusFifoData[(size_t) s1] = 0x20000 | (e.root << 8) | e.quality; geniusFifo.finishedWrite(1); }
    } else if (!(geniusChordOn && fits && now - geniusChangedAt < (long long) (0.18 * sampleRate))) {
        geniusChordOff(offset, out);
        geniusCount = cp::geniusVoicing(e.tones, e.numTones, e.root, n, geniusNotes, geniusPrevBass);
        if (geniusCount > 0) geniusPrevBass = geniusNotes[0];
        geniusNumTones = e.numTones; for (int i = 0; i < e.numTones; ++i) geniusTones[i] = e.tones[i];
        const auto vel = (juce::uint8) juce::jlimit(1, 127, (int) (m.getVelocity() * 0.62f));
        const bool synthOn = params.getRawParameterValue("synth")->load() > 0.5f;
        // Pianist touch: a quick roll from the bass up, the bass fuller than the inner voices.
        const int strumMs = std::max(12, (int) params.getRawParameterValue("strum")->load());
        for (int i = 0; i < geniusCount; ++i) {
            const int v = juce::jlimit(1, 127, (int) (m.getVelocity() * (i == 0 ? 0.72f : 0.5f)));
            const long long delay = (long long) (strumMs / 1000.0 * sampleRate * i);
            if (delay == 0) {
                if (synthOn) synth.noteOn(geniusNotes[i], v, 4);
                out.addEvent(juce::MidiMessage::noteOn(3, geniusNotes[i], (juce::uint8) v), offset);   // chords on MIDI channel 3
                pushPerf(juce::MidiMessage::noteOn(3, geniusNotes[i], (juce::uint8) v), offset, 3);
            } else enqueue(sampleClock + offset + delay, 0x92, geniusNotes[i], v, true);
        }
        juce::ignoreUnused(vel);
        geniusChordOn = true; geniusChangedAt = now;
        int s1, n1, s2, n2; geniusFifo.prepareToWrite(1, s1, n1, s2, n2);
        if (n1 > 0) { geniusFifoData[(size_t) s1] = 0x20000 | (e.root << 8) | e.quality; geniusFifo.finishedWrite(1); }
    }
    { int s1, n1, s2, n2; geniusFifo.prepareToWrite(1, s1, n1, s2, n2);
      if (n1 > 0) { geniusFifoData[(size_t) s1] = 0x10000 | n | (pressed << 8); geniusFifo.finishedWrite(1); } }
    pressedToSounding[(size_t) raw] = n;
    lastNoteAt = now;
    if (held[(size_t) n] > 0) handleMidi(juce::MidiMessage::noteOff(m.getChannel(), n), offset, out, false);
    handleMidi(juce::MidiMessage::noteOn(m.getChannel(), n, m.getVelocity()), offset, out, false);
}

void ChordPilotProcessor::playCustom(std::shared_ptr<const cp::Pattern> p) {
    std::atomic_store(&pattern, p);
    if (auto* par = params.getParameter("play")) par->setValueNotifyingHost(1.0f);
}

void ChordPilotProcessor::recordForInspiration(const juce::MidiMessage& m, int offset, bool hostMoving, double blockPpq, double samplesPerBeat) {
    int st = inspireState.load();
    if ((st != 1 && st != 2) || !(m.isNoteOn() || m.isNoteOff())) return;
    double stepPos;
    if (hostMoving) {
        // In a DAW: start at the next bar line, follow the project's timeline.
        double ppq = blockPpq + offset / samplesPerBeat;
        if (st == 1) { inspireStartPpq = std::ceil(ppq / 4.0 - 1e-6) * 4.0; inspireState = st = 2; }
        if (ppq < inspireStartPpq) return;
        stepPos = (ppq - inspireStartPpq) * 4.0;
    } else {
        // Standalone: start at the first note.
        long long now = sampleClock + offset;
        if (st == 1) { if (!m.isNoteOn()) return; inspireStartSample = now; inspireState = st = 2; inspireStartPpq = -1; }
        stepPos = (now - inspireStartSample) / (samplesPerBeat / 4.0);
    }
    const int step = (int) std::round(stepPos);
    if (step >= inspireBars * 16) { inspireState = 3; return; }
    int s1, n1, s2, n2; inspireFifo.prepareToWrite(1, s1, n1, s2, n2);
    if (n1 > 0) {
        inspireFifoData[(size_t) s1] = ((juce::int64) (m.isNoteOn() ? 1 : 0) << 40) | ((juce::int64) m.getNoteNumber() << 32)
                                     | ((juce::int64) m.getVelocity() << 24) | (juce::int64) std::max(0, step);
        inspireFifo.finishedWrite(1);
    }
}

bool ChordPilotProcessor::handleTwoHands(const juce::MidiMessage& m, int raw, int pressed, int offset, juce::MidiBuffer& out) {
    auto& slot = oneFingerHeld[(size_t) raw];
    if (m.isNoteOff()) {
        if (slot[0] == 0) return false;
        for (int i = 1; i <= slot[0]; ++i) {
            bool still = false;
            for (int k = 0; k < 128 && !still; ++k) if (k != raw) for (int j = 1; j <= oneFingerHeld[(size_t) k][0]; ++j) still |= oneFingerHeld[(size_t) k][(size_t) j] == slot[(size_t) i];
            if (!still) handleMidi(juce::MidiMessage::noteOff(m.getChannel(), slot[(size_t) i]), offset, out, false);
        }
        slot[0] = 0;
        return true;
    }
    auto table = std::atomic_load(&oneFinger);
    if (!table) return false;
    const int split = (int) params.getRawParameterValue("split")->load();
    const bool genius = params.getRawParameterValue("genius")->load() > 0.5f;
    const long long now = sampleClock + offset;
    const auto& e = (*table)[(size_t) cp::mod12(pressed)];
    int notes[8]; int cnt = 0; bool roll = false;
    if (pressed < split) {
        handRoot = genius ? e.leftRoot : e.root; handQuality = genius ? e.leftQuality : e.quality;
        cnt = cp::leftHandVoicing(handRoot, handQuality, pressed, split, notes);
        handNumTones = 0;
        for (int iv : cp::qualities()[(size_t) handQuality].iv) {
            int t = cp::mod12(handRoot + iv); bool dup = false;
            for (int j = 0; j < handNumTones; ++j) dup |= handTones[j] == t;
            if (!dup && handNumTones < 6) handTones[handNumTones++] = t;
        }
        handChordAt = now; roll = true;
        int s1, n1, s2, n2; geniusFifo.prepareToWrite(1, s1, n1, s2, n2);
        if (n1 > 0) { geniusFifoData[(size_t) s1] = 0x20000 | (handRoot << 8) | handQuality; geniusFifo.finishedWrite(1); }
    } else {
        bool leftHeld = false;
        for (int k = 0; k < 128 && !leftHeld; ++k) leftHeld = oneFingerHeld[(size_t) k][0] > 0 && k + (int) params.getRawParameterValue("transpose")->load() < split;
        const bool leftActive = handRoot >= 0 && (leftHeld || now - handChordAt < (long long) (2.5 * sampleRate));
        if (genius && leftActive) {
            int mel = pressed; bool found = false;
            for (int d : { 0, -1, 1, -2, 2 }) {
                int c = pressed + d; if (c < split) continue;
                for (int j = 0; j < handNumTones; ++j) if (handTones[j] == cp::mod12(c)) { mel = c; found = true; break; }
                if (found) break;
            }
            if (!found) { mel = pressed + e.lockShift; if (mel < split) mel = pressed; }
            cnt = cp::rightHandVoicing(handTones, handNumTones, handRoot, mel, split, notes);
            int s1, n1, s2, n2; geniusFifo.prepareToWrite(1, s1, n1, s2, n2);
            if (n1 > 0) { geniusFifoData[(size_t) s1] = 0x10000 | mel | (pressed << 8); geniusFifo.finishedWrite(1); }
        } else if (genius) {
            return false;    // right hand alone: full Genius mode
        } else {
            notes[0] = params.getRawParameterValue("scalelock")->load() > 0.5f ? juce::jlimit(0, 127, pressed + e.lockShift) : pressed;
            cnt = 1;
        }
    }
    if (params.getRawParameterValue("notesonly")->load() > 0.5f && cnt > 1) {
        // Single notes: the left hand plays just its bass (lowest note), the right hand just the melody (top note).
        if (pressed >= split) notes[0] = notes[cnt - 1];
        cnt = 1;
    }
    cnt = std::min(cnt, 9);
    slot[0] = cnt;
    const int strumMs = std::max(10, (int) params.getRawParameterValue("strum")->load());
    for (int i = 0; i < cnt; ++i) {
        slot[(size_t) (i + 1)] = notes[i];
        const float f = cnt == 1 ? 1.0f : pressed < split ? (i == 0 ? 0.8f : 0.55f) : (i == cnt - 1 ? 1.0f : 0.55f);
        const int vel = humanVel(juce::jlimit(1, 127, (int) (m.getVelocity() * f)));
        const long long delay = (roll ? (long long) (strumMs / 1000.0 * sampleRate * i) : 0) + humanDelay();
        if (delay == 0) handleMidi(juce::MidiMessage::noteOn(m.getChannel(), notes[i], (juce::uint8) vel), offset, out, false);
        else enqueue(sampleClock + offset + delay, (juce::uint8) (0x90 | (m.getChannel() - 1)), notes[i], vel, false);
    }
    return true;
}

void ChordPilotProcessor::newSong() {
    juce::Random r;
    const auto& g = cp::genres()[(size_t) genreIndex()];
    auto set = [this](const char* id, float v) { if (auto* p = params.getParameter(id)) p->setValueNotifyingHost(p->convertTo0to1(v)); };
    set("progression", (float) r.nextInt((int) g.progressions.size()));
    set("arp", (float) (1 + r.nextInt((int) cp::arpeggios().size())));
    set("melody", (float) (1 + r.nextInt(cp::kMelodyCount)));
    set("song", (float) (1 + r.nextInt(9999)));
    set("play", 1.0f);
}

void ChordPilotProcessor::playChord(const std::vector<int>& notes, bool on) {
    const juce::ScopedLock sl(chordLock);
    for (int n : notes)
        chordQueue.addEvent(on ? juce::MidiMessage::noteOn(16, n, (juce::uint8) 96) : juce::MidiMessage::noteOff(16, n), 0);
}

void ChordPilotProcessor::prepareToPlay(double sr, int samplesPerBlock) {
    sampleRate = sr;
    synth.prepare(sr);
    monoScratch.setSize(1, std::max(1, samplesPerBlock) * 2);
    fxScratch.setSize(2, std::max(1, samplesPerBlock) * 2);
    mapped.ensureSize(4096);
    isPlaying = false;
    audioPattern = std::atomic_load(&pattern);
}

void ChordPilotProcessor::handleMidi(const juce::MidiMessage& m, int offset, juce::MidiBuffer& out, bool fromPattern) {
    const bool suggestionLane = !fromPattern && m.getChannel() == 16;
    const bool melodyLane = fromPattern && m.getChannel() == 2;   // genre-player melody is sent on MIDI channel 2
    const bool geniusLane = fromPattern && m.getChannel() == 3;   // rolled Genius chords (delayed queue)
    // Recorder tracks: 0 your notes, 1 genre-player chords/arpeggio, 2 genre-player melody, 3 Genius chords.
    pushPerf(m, offset, geniusLane ? 3 : melodyLane ? 2 : fromPattern ? 1 : 0);
    if (geniusLane) {
        const bool synthOn = params.getRawParameterValue("synth")->load() > 0.5f;
        if (m.isNoteOn()) { if (synthOn) synth.noteOn(m.getNoteNumber(), m.getVelocity(), 4); }
        else if (m.isNoteOff()) synth.noteOff(m.getNoteNumber(), 4);
        out.addEvent(m, offset);
        return;
    }
    const int lane = fromPattern ? (melodyLane ? 3 : 1) : (suggestionLane ? 2 : 0);
    auto& patArray = melodyLane ? melodyNotes : patternNotes;
    const bool synthOn = params.getRawParameterValue("synth")->load() > 0.5f;
    if (m.isNoteOn()) {
        int n = m.getNoteNumber();
        if (fromPattern) patArray[(size_t) n] = (uint8_t) m.getVelocity();
        else if (!suggestionLane) {
            held[(size_t) n] = (uint8_t) std::max<int>(1, m.getVelocity());
            int s1, n1, s2, n2; noteFifo.prepareToWrite(1, s1, n1, s2, n2);
            if (n1 > 0) { noteFifoData[(size_t) s1] = n | (m.getVelocity() << 8); noteFifo.finishedWrite(1); }
        }
        if (synthOn) synth.noteOn(n, m.getVelocity(), lane);
    } else if (m.isNoteOff()) {
        int n = m.getNoteNumber();
        if (fromPattern) patArray[(size_t) n] = 0; else if (!suggestionLane) held[(size_t) n] = 0;
        synth.noteOff(n, lane);
    } else if (m.isSustainPedalOn() || m.isSustainPedalOff()) {
        synth.setSustain(m.isSustainPedalOn());
    } else if (m.isAllNotesOff() || m.isAllSoundOff()) {
        synth.allNotesOff();
        for (auto& h : held) h = 0;
    }
    out.addEvent(m, offset);
}

void ChordPilotProcessor::releasePattern(int offset, juce::MidiBuffer& out) {
    for (int n = 0; n < 128; ++n) {
        if (patternNotes[(size_t) n] > 0) handleMidi(juce::MidiMessage::noteOff(1, n), offset, out, true);
        if (melodyNotes[(size_t) n] > 0) handleMidi(juce::MidiMessage::noteOff(2, n), offset, out, true);
    }
}

void ChordPilotProcessor::fireStep(int step, const cp::Pattern& p, int offset, juce::MidiBuffer& out) {
    if (step == 0) cursor = 0;
    patternChordIndex = step / std::max(1, p.stepsPerChord);
    while (cursor < p.events.size() && p.events[cursor].step < step) ++cursor;
    const int swing = (int) params.getRawParameterValue("swing")->load();
    const int strum = (int) params.getRawParameterValue("strum")->load();
    const int human = (int) params.getRawParameterValue("humanize")->load();
    if (swing > 0 || strum > 0 || human > 0) {
        const double spStep = sampleRate * 60.0 / std::max(20.0, (double) params.getRawParameterValue("bpm")->load()) / 4.0;
        const long long base = sampleClock + offset + ((step % 2 == 1) ? (long long) (spStep * swing / 100.0) : 0);
        int chordIdx = 0;
        while (cursor < p.events.size() && p.events[cursor].step == step) {
            const auto& e = p.events[cursor++];
            const juce::uint8 ch = e.lane == 1 ? 1 : 0;
            if (e.vel > 0) {
                long long st = e.lane == 1 ? 0 : (long long) (strum / 1000.0 * sampleRate * chordIdx++);
                enqueue(base + st + humanDelay(), (juce::uint8) (0x90 | ch), e.note, humanVel(e.vel), true);
            } else enqueue(base, (juce::uint8) (0x80 | ch), e.note, 0, true);
        }
        return;
    }
    while (cursor < p.events.size() && p.events[cursor].step == step) {
        const auto& e = p.events[cursor++];
        const int ch = e.lane == 1 ? 2 : 1;
        auto& arr = e.lane == 1 ? melodyNotes : patternNotes;
        if (e.vel > 0) handleMidi(juce::MidiMessage::noteOn(ch, e.note, (juce::uint8) e.vel), offset, out, true);
        else if (arr[(size_t) e.note] > 0) handleMidi(juce::MidiMessage::noteOff(ch, e.note), offset, out, true);
    }
}

void ChordPilotProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi) {
    juce::ScopedNoDenormals noDenormals;
    const int n = buffer.getNumSamples();
    buffer.clear();
    synth.setModel(pianoIndex());

    // On-screen keyboard and tapped suggestions join the incoming MIDI.
    keyboardState.processNextMidiBuffer(midi, 0, n, true);
    {
        const juce::ScopedTryLock tl(chordLock);
        if (tl.isLocked() && !chordQueue.isEmpty()) { midi.addEvents(chordQueue, 0, -1, 0); chordQueue.clear(); }
    }

    // Pattern swap.
    auto latest = std::atomic_load(&pattern);
    juce::MidiBuffer out;
    if (latest != audioPattern) {
        releasePattern(0, out);
        audioPattern = latest;
        cursor = 0;
        if (audioPattern) { auto s = (int) (nextStep % std::max(1, audioPattern->total)); while (cursor < audioPattern->events.size() && audioPattern->events[cursor].step < s) ++cursor; }
    }

    // Transport.
    double tempo = params.getRawParameterValue("bpm")->load();
    bool hostMoving = false, hasHostClock = false; double hostPpq = 0;
    if (params.getRawParameterValue("sync")->load() > 0.5f)
        if (auto* ph = getPlayHead())
            if (auto pos = ph->getPosition()) {
                if (auto b = pos->getBpm()) { tempo = *b; hasHostClock = true; }
                if (auto q = pos->getPpqPosition()) hostPpq = *q;
                hostMoving = pos->getIsPlaying();
            }
    if (auto* ph = getPlayHead())   // DAW pressed REC: start a fresh take aligned to the DAW timeline
        if (auto pos = ph->getPosition()) {
            const bool rec = pos->getIsRecording();
            if (rec && !hostWasRecording) {
                perfStartPpq = pos->getPpqPosition().orFallback(-1.0);
                pushPerf(juce::MidiMessage(), 0, 254);
            }
            hostWasRecording = rec;
        }
    const bool followHost = hasHostClock && hostMoving && !juce::JUCEApplicationBase::isStandaloneApp();
    const bool wantPlay = params.getRawParameterValue("play")->load() > 0.5f;
    auto seek = [&] {
        cursor = 0;
        if (!audioPattern) return;
        auto s = (int) (nextStep % std::max(1, audioPattern->total));
        while (cursor < audioPattern->events.size() && audioPattern->events[cursor].step < s) ++cursor;
    };
    if (wantPlay && !isPlaying) {
        isPlaying = true; stepPhase = followHost ? hostPpq * 4 : 0;
        nextStep = (long long) std::ceil(stepPhase - 1e-9); seek();
    } else if (!wantPlay && isPlaying) {
        isPlaying = false;
        for (auto& d : delayed) if (d.pattern && d.st != 0x92) d.active = false;
        releasePattern(0, out);
    }
    const double samplesPerStep = sampleRate * 60.0 / std::max(20.0, tempo) / 4.0;
    if (isPlaying && followHost && std::abs(hostPpq * 4 - stepPhase) > 0.5) {
        releasePattern(0, out); stepPhase = hostPpq * 4; nextStep = (long long) std::ceil(stepPhase - 1e-9); seek();
    }
    const double phaseStart = stepPhase, phaseEnd = stepPhase + n / samplesPerStep;

    if (buffer.getNumChannels() == 0) {   // MIDI-effect build: no audio bus, render into a silent scratch buffer
        if (fxScratch.getNumSamples() < n) fxScratch.setSize(2, n, false, false, true);
        fxScratch.clear();
    }
    float* L = buffer.getNumChannels() > 0 ? buffer.getWritePointer(0) : fxScratch.getWritePointer(0);
    float* R = buffer.getNumChannels() > 1 ? buffer.getWritePointer(1) : (buffer.getNumChannels() == 0 ? fxScratch.getWritePointer(1) : nullptr);
    if (!R) { // mono layout: render the right channel into a pre-allocated throw-away buffer
        if (monoScratch.getNumSamples() < n) monoScratch.setSize(1, n, false, false, true);
        monoScratch.clear(); R = monoScratch.getWritePointer(0);
    }

    perfSampleRate = sampleRate;
    auto it = midi.cbegin();
    int done = 0;
    while (done < n) {
        int nextEvent = n;
        if (it != midi.cend()) nextEvent = juce::jlimit(done, n - 1, (*it).samplePosition);
        int nextStepOff = n;
        const bool stepDue = isPlaying && audioPattern && audioPattern->total > 0 && (double) nextStep < phaseEnd;
        if (stepDue) nextStepOff = juce::jlimit(done, n - 1, (int) std::ceil(((double) nextStep - phaseStart) * samplesPerStep));
        const int nextDelayed = nextDelayedOffset(done, n);
        int next = std::min({ nextEvent, nextStepOff, nextDelayed });
        if (next > done) { synth.render(L, R, done, next); done = next; }
        if (next >= n) break;
        if (nextDelayed == next) runDelayed(next, out);
        if (it != midi.cend() && nextEvent == next) {
            recordForInspiration((*it).getMessage(), next, hostMoving && hasHostClock, hostPpq, sampleRate * 60.0 / std::max(20.0, tempo));
            handleInput((*it).getMessage(), next, out); ++it;
        }
        if (stepDue && nextStepOff == next) { fireStep((int) (nextStep % audioPattern->total), *audioPattern, next, out); ++nextStep; }
    }
    for (; it != midi.cend(); ++it) handleInput((*it).getMessage(), n - 1, out);
    // Genius chord fades out 1.8 s after the last key is released.
    if (geniusChordOn) {
        bool anyHeld = false; for (auto& h : held) anyHeld |= h.load() > 0;
        bool genius = params.getRawParameterValue("genius")->load() > 0.5f;
        if (!genius || (!anyHeld && sampleClock + n - lastNoteAt > (long long) (1.8 * sampleRate))) geniusChordOff(n - 1, out);
        else if (anyHeld) lastNoteAt = sampleClock + n;
    }
    sampleClock += n;
    // Inspiration recording ends after the chosen number of bars.
    if (inspireState.load() == 2) {
        const double spb = sampleRate * 60.0 / std::max(20.0, tempo);
        bool over = (hostMoving && hasHostClock && inspireStartPpq >= 0) ? (hostPpq + n / spb - inspireStartPpq) * 4.0 >= inspireBars * 16
                  : (inspireStartSample >= 0 && (sampleClock - inspireStartSample) / (spb / 4.0) >= inspireBars * 16);
        if (over) inspireState = 3;
    }
    if (isPlaying) stepPhase = phaseEnd;

    const float target = params.getRawParameterValue("volume")->load();
    for (int i = 0; i < n && buffer.getNumChannels() > 0; ++i) {
        smoothedVolume += (target - smoothedVolume) * 0.002f;
        auto clip = [](float x) { x = juce::jlimit(-1.0f, 1.0f, x); return x - x * x * x / 6.0f; };
        L[i] = clip(L[i] * smoothedVolume);
        if (buffer.getNumChannels() > 1) R[i] = clip(R[i] * smoothedVolume);
    }
    // Single-channel MIDI out (to play one instrument of the DAW with everything ChordPilot generates).
    const int chan = (int) params.getRawParameterValue("midichan")->load();
    if (chan > 0) {
        mapped.clear();
        for (const auto meta : out) {
            auto msg = meta.getMessage();
            if (msg.getChannel() > 0) msg.setChannel(chan);
            mapped.addEvent(msg, meta.samplePosition);
        }
        out.swapWith(mapped);
    }
    if (auto* vo = virtualOutPtr.load())
        if (!out.isEmpty() && (juce::JUCEApplicationBase::isStandaloneApp() || params.getRawParameterValue("vport")->load() > 0.5f))
            vo->sendBlockOfMessagesNow(out);
    midi.swapWith(out);
}

juce::AudioProcessorEditor* ChordPilotProcessor::createEditor() { return new ChordPilotEditor(*this); }

void ChordPilotProcessor::getStateInformation(juce::MemoryBlock& destData) {
    if (auto xml = params.copyState().createXml()) copyXmlToBinary(*xml, destData);
}

void ChordPilotProcessor::setStateInformation(const void* data, int sizeInBytes) {
    if (auto xml = getXmlFromBinary(data, sizeInBytes))
        if (xml->hasTagName(params.state.getType())) params.replaceState(juce::ValueTree::fromXml(*xml));
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new ChordPilotProcessor(); }
