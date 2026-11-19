#include "PluginProcessor.h"
#include "PluginEditor.h"

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
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "synth", 1 }, "Pianoforte interno", true));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "sync", 1 }, "Sync DAW", true));
    l.add(std::make_unique<AudioParameterBool>(ParameterID { "play", 1 }, "Genre Player", false));
    l.add(std::make_unique<AudioParameterInt>(ParameterID { "progression", 1 }, "Progressione", 0, 5, 0));
    l.add(std::make_unique<AudioParameterFloat>(ParameterID { "bpm", 1 }, "BPM", NormalisableRange<float>(40, 220, 1), 110));
    return l;
}
}

ChordPilotProcessor::ChordPilotProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      params(*this, nullptr, "ChordPilot", makeLayout()) {
    for (auto& a : held) a = 0;
    for (auto& a : patternNotes) a = 0;
    rebuildPattern();
    startTimerHz(15);
}

ChordPilotProcessor::~ChordPilotProcessor() { stopTimer(); }

bool ChordPilotProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const {
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

// Runs on the message thread: rebuild the genre-player loop when a musical setting changes.
void ChordPilotProcessor::timerCallback() {
    std::array<int, 6> now { genreIndex(), (int) params.getRawParameterValue("key")->load(),
                             (int) params.getRawParameterValue("minor")->load(), (int) params.getRawParameterValue("complexity")->load(),
                             (int) params.getRawParameterValue("progression")->load(), 0 };
    int det = detectedKeyCode.load();
    if (now[0] != lastParamState[0]) {
        // New genre: adopt its typical tempo.
        if (lastParamState[0] >= 0)
            if (auto* p = params.getParameter("bpm")) p->setValueNotifyingHost(p->convertTo0to1((float) cp::genres()[(size_t) now[0]].bpm));
    }
    if (now != lastParamState || (now[1] == 0 && det != lastDetected)) {
        lastParamState = now; lastDetected = det;
        rebuildPattern();
    }
}

void ChordPilotProcessor::rebuildPattern() {
    const auto& g = cp::genres()[(size_t) juce::jlimit(0, (int) cp::genres().size() - 1, genreIndex())];
    int prog = juce::jlimit(0, (int) g.progressions.size() - 1, (int) params.getRawParameterValue("progression")->load());
    auto p = std::make_shared<const cp::Pattern>(cp::buildPattern(g, playerKey(), prog, (int) params.getRawParameterValue("complexity")->load()));
    std::atomic_store(&pattern, p);
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
    isPlaying = false;
    audioPattern = std::atomic_load(&pattern);
}

void ChordPilotProcessor::handleMidi(const juce::MidiMessage& m, int offset, juce::MidiBuffer& out, bool fromPattern) {
    const bool suggestionLane = !fromPattern && m.getChannel() == 16;
    const int lane = fromPattern ? 1 : (suggestionLane ? 2 : 0);
    const bool synthOn = params.getRawParameterValue("synth")->load() > 0.5f;
    if (m.isNoteOn()) {
        int n = m.getNoteNumber();
        if (fromPattern) patternNotes[(size_t) n] = (uint8_t) m.getVelocity();
        else if (!suggestionLane) {
            held[(size_t) n] = (uint8_t) std::max<int>(1, m.getVelocity());
            int s1, n1, s2, n2; noteFifo.prepareToWrite(1, s1, n1, s2, n2);
            if (n1 > 0) { noteFifoData[(size_t) s1] = n | (m.getVelocity() << 8); noteFifo.finishedWrite(1); }
        }
        if (synthOn) synth.noteOn(n, m.getVelocity(), lane);
    } else if (m.isNoteOff()) {
        int n = m.getNoteNumber();
        if (fromPattern) patternNotes[(size_t) n] = 0; else if (!suggestionLane) held[(size_t) n] = 0;
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
    for (int n = 0; n < 128; ++n)
        if (patternNotes[(size_t) n] > 0) handleMidi(juce::MidiMessage::noteOff(1, n), offset, out, true);
}

void ChordPilotProcessor::fireStep(int step, const cp::Pattern& p, int offset, juce::MidiBuffer& out) {
    if (step == 0) cursor = 0;
    patternChordIndex = step / std::max(1, p.stepsPerChord);
    while (cursor < p.events.size() && p.events[cursor].step < step) ++cursor;
    while (cursor < p.events.size() && p.events[cursor].step == step) {
        const auto& e = p.events[cursor++];
        if (e.vel > 0) handleMidi(juce::MidiMessage::noteOn(1, e.note, (juce::uint8) e.vel), offset, out, true);
        else if (patternNotes[(size_t) e.note] > 0) handleMidi(juce::MidiMessage::noteOff(1, e.note), offset, out, true);
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
        isPlaying = false; releasePattern(0, out);
    }
    const double samplesPerStep = sampleRate * 60.0 / std::max(20.0, tempo) / 4.0;
    if (isPlaying && followHost && std::abs(hostPpq * 4 - stepPhase) > 0.5) {
        releasePattern(0, out); stepPhase = hostPpq * 4; nextStep = (long long) std::ceil(stepPhase - 1e-9); seek();
    }
    const double phaseStart = stepPhase, phaseEnd = stepPhase + n / samplesPerStep;

    float* L = buffer.getWritePointer(0);
    float* R = buffer.getNumChannels() > 1 ? buffer.getWritePointer(1) : nullptr;
    if (!R) { // mono layout: render the right channel into a pre-allocated throw-away buffer
        if (monoScratch.getNumSamples() < n) monoScratch.setSize(1, n, false, false, true);
        monoScratch.clear(); R = monoScratch.getWritePointer(0);
    }

    auto it = midi.cbegin();
    int done = 0;
    while (done < n) {
        int nextEvent = n;
        if (it != midi.cend()) nextEvent = juce::jlimit(done, n - 1, (*it).samplePosition);
        int nextStepOff = n;
        const bool stepDue = isPlaying && audioPattern && audioPattern->total > 0 && (double) nextStep < phaseEnd;
        if (stepDue) nextStepOff = juce::jlimit(done, n - 1, (int) std::ceil(((double) nextStep - phaseStart) * samplesPerStep));
        int next = std::min(nextEvent, nextStepOff);
        if (next > done) { synth.render(L, R, done, next); done = next; }
        if (next >= n) break;
        if (it != midi.cend() && nextEvent == next) { handleMidi((*it).getMessage(), next, out, false); ++it; }
        if (stepDue && nextStepOff == next) { fireStep((int) (nextStep % audioPattern->total), *audioPattern, next, out); ++nextStep; }
    }
    for (; it != midi.cend(); ++it) handleMidi((*it).getMessage(), n - 1, out, false);
    if (isPlaying) stepPhase = phaseEnd;

    const float target = params.getRawParameterValue("volume")->load();
    for (int i = 0; i < n; ++i) {
        smoothedVolume += (target - smoothedVolume) * 0.002f;
        auto clip = [](float x) { x = juce::jlimit(-1.0f, 1.0f, x); return x - x * x * x / 6.0f; };
        L[i] = clip(L[i] * smoothedVolume);
        if (buffer.getNumChannels() > 1) R[i] = clip(R[i] * smoothedVolume);
    }
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
