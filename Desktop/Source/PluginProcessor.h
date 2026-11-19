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
    bool isMidiEffect() const override { return false; }
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
    std::array<std::atomic<uint8_t>, 128> patternNotes {}; // notes from the genre player
    std::atomic<int> patternChordIndex { 0 };
    std::atomic<int> detectedKeyCode { -1 };               // tonic + 12*minor, set by the editor in Auto mode
    juce::AbstractFifo noteFifo { 512 };                   // audio → editor: note-ons for key detection
    std::array<int, 512> noteFifoData {};

    int genreIndex() const;
    int pianoIndex() const;
    cp::Key playerKey() const;
    std::shared_ptr<const cp::Pattern> currentPattern() const { return std::atomic_load(&pattern); }
    void playChord(const std::vector<int>& notes, bool on); // tapped suggestion (sent on MIDI channel 16)

private:
    void timerCallback() override;
    void rebuildPattern();
    void handleMidi(const juce::MidiMessage& m, int offset, juce::MidiBuffer& out, bool fromPattern);
    void fireStep(int step, const cp::Pattern& p, int offset, juce::MidiBuffer& out);
    void releasePattern(int offset, juce::MidiBuffer& out);

    PianoSynth synth;
    std::shared_ptr<const cp::Pattern> pattern;            // swapped atomically (message thread → audio thread)
    std::shared_ptr<const cp::Pattern> audioPattern;       // audio thread's copy
    std::array<int, 6> lastParamState { -1, -1, -1, -1, -1, -1 };
    int lastDetected = -2;

    double sampleRate = 44100;
    bool isPlaying = false;
    double stepPhase = 0;
    long long nextStep = 0;
    size_t cursor = 0;
    float smoothedVolume = 0.8f;
    juce::AudioBuffer<float> monoScratch;
    juce::MidiBuffer chordQueue;                            // notes from tapped suggestions
    juce::CriticalSection chordLock;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ChordPilotProcessor)
};
