#pragma once
#include <JuceHeader.h>
#include "Engine.h"
#include "PianoSynth.h"
#include <array>
#include <atomic>
#include <memory>

/// ChordPilot desktop processor: VST3 / AU / Standalone.
/// Plays its own piano, passes MIDI through, and runs the genre player (sent to MIDI out, synced to the DAW).
class ChordPilotProcessor : public juce::AudioProcessor, private juce::Timer {
public:
    ChordPilotProcessor();
    ~ChordPilotProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override {}
    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }
    const juce::String getName() const override { return "ChordPilot"; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return true; }
#if CHORDPILOT_MIDI_FX
    bool isMidiEffect() const override { return true; }    // "ChordPilot MIDI": drives any instrument of the DAW
#else
    bool isMidiEffect() const override { return false; }
#endif
    double getTailLengthSeconds() const override { return 2.0; }

    int getNumPrograms() override { return (int) cp::genres().size(); }
    int getCurrentProgram() override { return genreIndex(); }
    void setCurrentProgram(int index) override;
    const juce::String getProgramName(int index) override;
    void changeProgramName(int, const juce::String&) override {}

    void getStateInformation(juce::MemoryBlock& destData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    // ---- Shared with the editor ----
    juce::AudioProcessorValueTreeState params;
    juce::MidiKeyboardState keyboardState;                 // on-screen keyboard → audio thread
    std::array<std::atomic<uint8_t>, 128> held {};         // notes the musician holds
    std::array<std::atomic<uint8_t>, 128> patternNotes {}; // accompaniment notes from the genre player
    std::array<std::atomic<uint8_t>, 128> melodyNotes {};  // melody notes from the genre player
    std::atomic<int> patternChordIndex { 0 };
    std::atomic<int> detectedKeyCode { -1 };               // tonic + 12*minor, set by the editor in Auto mode
    juce::AbstractFifo noteFifo { 512 };                   // audio → editor: note-ons for key detection
    std::array<int, 512> noteFifoData {};

    int genreIndex() const;
    int pianoIndex() const;
    cp::Key playerKey() const;
    std::shared_ptr<const cp::Pattern> currentPattern() const { return std::atomic_load(&pattern); }
    void playChord(const std::vector<int>& notes, bool on); // tapped suggestion (sent on MIDI channel 16)
    void newSong();                                         // random progression + arpeggio + melody + variation

    // ---- Inspiration: record the track (MIDI the plug-in receives), then suggest 10 melodies ----
    std::atomic<int> inspireState { 0 };                    // 0 idle, 1 armed, 2 recording, 3 done
    int inspireBars = 4;
    juce::AbstractFifo inspireFifo { 4096 };                // audio → editor: packed (on, note, vel, step)
    std::array<juce::int64, 4096> inspireFifoData {};
    void armInspiration(int bars) { inspireBars = bars; inspireState = 1; }
    /// Plays a ready-made loop (track + suggested melody) with the genre player until a setting changes.
    void playCustom(std::shared_ptr<const cp::Pattern> p);

    /// Genius mode lookup for one pitch class (built on the message thread, read by the audio thread).
    /// Genius mode lookup for every key (built on the message thread from the melodic memory, read by the audio thread).
    struct GeniusEntry { int note = 0; int root = 0; int quality = 0; int tones[6] {}; int numTones = 0; };
    using GeniusTable = std::array<GeniusEntry, 128>;

private:
    void timerCallback() override;
    void rebuildPattern();
    void handleMidi(const juce::MidiMessage& m, int offset, juce::MidiBuffer& out, bool fromPattern);
    void fireStep(int step, const cp::Pattern& p, int offset, juce::MidiBuffer& out);
    void releasePattern(int offset, juce::MidiBuffer& out);
    void handleInput(const juce::MidiMessage& m, int offset, juce::MidiBuffer& out);
    void geniusChordOff(int offset, juce::MidiBuffer& out);
    void rebuildGeniusTable();
    void enqueue(long long due, juce::uint8 st, int note, int vel, bool fromPattern);
    int nextDelayedOffset(int done, int n) const;
    void runDelayed(int offset, juce::MidiBuffer& out);
    int humanVel(int v);
    long long humanDelay();

    // Pro options: delayed-event queue (strum, humanize, swing), one-finger chords, scale lock
    struct Delayed { long long due; juce::uint8 st; juce::uint8 note; juce::uint8 vel; bool pattern; bool active; };
    std::array<Delayed, 1024> delayed {};
    struct OneFingerEntry { int root = 0; int quality = 0; int tones[6] {}; int numTones = 0; int lockShift = 0;
                            int leftRoot = 0; int leftQuality = 0; };   // left-hand chord in Genius two-hands mode
    using OneFingerTable = std::array<OneFingerEntry, 12>;
    std::shared_ptr<const OneFingerTable> oneFinger;        // swapped atomically
    std::array<std::array<int, 10>, 128> oneFingerHeld {};  // pressed key → chord notes (count in [0])
    juce::Random rng;

    // Genius mode
    cp::Engine geniusEngine;                                // message thread
    std::shared_ptr<const GeniusTable> geniusTable;         // swapped atomically
    juce::AbstractFifo geniusFifo { 256 };                  // audio → message thread: notes and chosen chords
    std::array<int, 256> geniusFifoData {};
    std::array<int, 128> pressedToSounding {};
    int geniusNotes[8] {}; int geniusCount = 0; int geniusTones[6] {}; int geniusNumTones = 0;
    long long geniusChangedAt = -1000000, lastNoteAt = 0, sampleClock = 0;
    int geniusPrevBass = -1;
    // Two hands
    int handRoot = -1, handQuality = 0, handTones[6] {}, handNumTones = 0; long long handChordAt = -1000000;
    bool handleTwoHands(const juce::MidiMessage& m, int raw, int pressed, int offset, juce::MidiBuffer& out);
public:
    /// Pianist mode: suggested next melody notes (message thread only).
    std::vector<cp::Engine::GeniusNext> geniusSuggestions() { return geniusEngine.geniusNext(); }
    std::atomic<int> geniusVersion { 0 };          // bumps when the suggestions should be refreshed
private:
    bool geniusChordOn = false;
    double inspireStartPpq = -1; long long inspireStartSample = -1;
    void recordForInspiration(const juce::MidiMessage& m, int offset, bool hostMoving, double blockPpq, double samplesPerBeat);
    int lastGeniusGenre = -1, geniusDirty = 1;

    PianoSynth synth;
    std::shared_ptr<const cp::Pattern> pattern;            // swapped atomically (message thread → audio thread)
    std::shared_ptr<const cp::Pattern> audioPattern;       // audio thread's copy
    std::array<int, 8> lastParamState { -1, -1, -1, -1, -1, -1, -1, -1 };
    int lastDetected = -2;

    double sampleRate = 44100;
    bool isPlaying = false;
    double stepPhase = 0;
    long long nextStep = 0;
    size_t cursor = 0;
    float smoothedVolume = 0.8f;
    juce::AudioBuffer<float> monoScratch;
    juce::AudioBuffer<float> fxScratch;                     // MIDI-effect build: the piano renders here (not heard)
    juce::MidiBuffer mapped;                                // MIDI out remapped to a single channel
    juce::MidiBuffer chordQueue;                            // notes from tapped suggestions
    juce::CriticalSection chordLock;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ChordPilotProcessor)
};
