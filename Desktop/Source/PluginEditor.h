#pragma once
#include "PluginProcessor.h"

namespace aurora {
const juce::Colour night { 0xff050b1a }, deep { 0xff0b1736 }, panel { 0xa0101e40 }, line { 0x298cbeff },
    fg { 0xffeaf2ff }, muted { 0xff9fb2d6 }, green { 0xff3dffb0 }, teal { 0xff19d3c5 }, cyan { 0xff5cd6ff },
    violet { 0xff8e6cff }, magenta { 0xffe05bff }, pink { 0xffff6fb5 };
}

class AuroraLookAndFeel : public juce::LookAndFeel_V4 {
public:
    AuroraLookAndFeel();
    void drawComboBox(juce::Graphics&, int w, int h, bool down, int, int, int, int, juce::ComboBox&) override;
    void drawButtonBackground(juce::Graphics&, juce::Button&, const juce::Colour&, bool over, bool down) override;
    juce::Font getComboBoxFont(juce::ComboBox&) override { return juce::Font(juce::FontOptions(15.0f, juce::Font::bold)); }
};

/// Piano keyboard that glows on the suggested notes; multi-touch and glissando.
class KeyboardView : public juce::Component {
public:
    explicit KeyboardView(ChordPilotProcessor& p) : proc(p) {}
    int lowest = 48, octaves = 3;
    std::map<int, cp::Highlight> highlights;
    std::set<int> held, pattern, melody;
    std::map<int, juce::String> geniusNext;   // note → chord name (Pianist mode suggestions)
    bool italian = true, showScale = true, flats = false;
    void paint(juce::Graphics&) override;
    void mouseDown(const juce::MouseEvent&) override;
    void mouseDrag(const juce::MouseEvent&) override;
    void mouseUp(const juce::MouseEvent&) override;
private:
    ChordPilotProcessor& proc;
    std::map<int, int> touches;  // source index → note
    bool isBlack(int n) const { int pc = cp::mod12(n); return pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10; }
    juce::Rectangle<float> keyRect(int n) const;
    int noteAt(juce::Point<float> p, int& velocity) const;
};

class SuggestionCard : public juce::Component {
public:
    std::function<void()> onTap;
    cp::Suggestion s; bool valid = false; juce::String name;
    void paint(juce::Graphics&) override;
    void mouseDown(const juce::MouseEvent&) override { if (valid && onTap) onTap(); }
};

/// Pro options panel (Scaler / Captain Chords / InstaChord-style extras). All controls are host parameters.
class ProPanel : public juce::Component {
public:
    explicit ProPanel(ChordPilotProcessor& p);
    void paint(juce::Graphics&) override;
    void resized() override;
private:
    juce::ToggleButton oneFinger { "Accordi con un dito" }, scaleLock { "Blocca scala" };
    juce::Slider strum, humanize, swing, transpose;
    juce::Label strumL, humanizeL, swingL, transposeL;
    juce::ComboBox voicing;
    using CA = juce::AudioProcessorValueTreeState::ComboBoxAttachment;
    using BA = juce::AudioProcessorValueTreeState::ButtonAttachment;
    using SA = juce::AudioProcessorValueTreeState::SliderAttachment;
    std::unique_ptr<BA> a1, a2; std::unique_ptr<SA> s1, s2, s3, s4; std::unique_ptr<CA> c1;
};

/// Drag this button into the DAW to drop the current song as a MIDI file; click to save it.
class MidiDragButton : public juce::TextButton {
public:
    explicit MidiDragButton(ChordPilotProcessor& p) : juce::TextButton("Trascina MIDI nella DAW"), proc(p) {}
    /// Optional custom source (e.g. an Inspiration option) and file name.
    std::function<std::shared_ptr<const cp::Pattern>()> source;
    juce::String fileName;
    juce::File writeMidi() const;
    void mouseDrag(const juce::MouseEvent&) override;
    void clicked() override;
private:
    ChordPilotProcessor& proc;
    bool dragging = false;
    std::unique_ptr<juce::FileChooser> chooser;
};

/// Inspiration: records the track, then offers 10 melodies that follow it (listen / drag to the DAW).
class InspirePanel : public juce::Component, private juce::Timer {
public:
    explicit InspirePanel(ChordPilotProcessor& p);
    ~InspirePanel() override { stopTimer(); }
    void paint(juce::Graphics&) override;
    void resized() override;
private:
    void timerCallback() override;
    void analyse();
    ChordPilotProcessor& proc;
    juce::TextButton rec4 { "Registra 4 battute" }, rec8 { "Registra 8 battute" }, fromPlayer { "Usa il Genre Player" };
    juce::Label status;
    std::vector<cp::RecordedNote> recorded; std::map<int, std::pair<int, int>> openNotes;  // note → (step, vel)
    int total = 64;
    std::vector<std::shared_ptr<const cp::Pattern>> optionPatterns;
    juce::OwnedArray<juce::TextButton> listenButtons;
    juce::OwnedArray<MidiDragButton> dragButtons;
    juce::StringArray names;
};

class ChordPilotEditor : public juce::AudioProcessorEditor, public juce::DragAndDropContainer, private juce::Timer {
public:
    explicit ChordPilotEditor(ChordPilotProcessor&);
    ~ChordPilotEditor() override;
    void paint(juce::Graphics&) override;
    void resized() override;

private:
    void timerCallback() override;
    void recompute();
    void syncEngine();
    juce::String chordName(const cp::Chord& c) const;
    void autoConnectStandaloneMidi();

    ChordPilotProcessor& proc;
    AuroraLookAndFeel lnf;
    cp::Engine engine;
    cp::Result result;
    std::set<int> held, pattern, melody;
    std::optional<cp::Chord> lastCommitted;
    juce::uint32 heldChangedAt = 0;
    int tick = 0;
    int lastGeniusVersion = -1;

    juce::ComboBox genreBox, pianoBox, keyBox, complexityBox, progressionBox, arpBox, melodyBox;
    juce::ToggleButton minorToggle { "Minore" }, synthToggle { "Piano interno" }, syncToggle { "Sync DAW" }, italianToggle { "Do Re Mi" };
    juce::TextButton playButton { "Genre Player" }, newSongButton { "Nuova canzone" }, geniusButton { "Modalita Genio" }, octDown { "<" }, octUp { ">" };
    juce::TextButton proButton { "Pro" }, inspireButton { "Ispirazione" };
    juce::ToggleButton drumsToggle { "Batteria" }, handsToggle { "Due mani" }, notesToggle { "Solo note" };
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> drumsA, handsA, notesA;
    MidiDragButton midiButton { proc };
    juce::Slider bpmSlider;
    std::array<SuggestionCard, 6> cards;
    KeyboardView keyboard;
    using CA = juce::AudioProcessorValueTreeState::ComboBoxAttachment;
    using BA = juce::AudioProcessorValueTreeState::ButtonAttachment;
    using SA = juce::AudioProcessorValueTreeState::SliderAttachment;
    std::unique_ptr<CA> genreA, pianoA, keyA, cxA, progA, arpA, melA;
    std::unique_ptr<BA> minorA, synthA, syncA, playA, geniusA;
    std::unique_ptr<SA> bpmA;
    juce::Rectangle<int> statusArea, playerArea;
    float auroraPhase = 0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ChordPilotEditor)
};
