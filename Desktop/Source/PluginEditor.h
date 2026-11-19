#pragma once
#include "PluginProcessor.h"

namespace aurora {
const juce::Colour night { 0xff050b1a }, deep { 0xff0b1736 }, panel { 0xa0101e40 }, line { 0x298cbeff },
    fg { 0xffeaf2ff }, muted { 0xff9fb2d6 }, green { 0xff3dffb0 }, teal { 0xff19d3c5 }, cyan { 0xff5cd6ff },
    violet { 0xff8e6cff }, magenta { 0xffe05bff };
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
    std::set<int> held, pattern;
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

class ChordPilotEditor : public juce::AudioProcessorEditor, private juce::Timer {
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
    std::set<int> held, pattern;
    std::optional<cp::Chord> lastCommitted;
    juce::uint32 heldChangedAt = 0;
    int tick = 0;

    juce::ComboBox genreBox, pianoBox, keyBox, complexityBox, progressionBox;
    juce::ToggleButton minorToggle { "Minore" }, synthToggle { "Piano interno" }, syncToggle { "Sync DAW" }, italianToggle { "Do Re Mi" };
    juce::TextButton playButton { "Genre Player" }, octDown { "<" }, octUp { ">" };
    juce::Slider bpmSlider;
    std::array<SuggestionCard, 6> cards;
    KeyboardView keyboard;
    using CA = juce::AudioProcessorValueTreeState::ComboBoxAttachment;
    using BA = juce::AudioProcessorValueTreeState::ButtonAttachment;
    using SA = juce::AudioProcessorValueTreeState::SliderAttachment;
    std::unique_ptr<CA> genreA, pianoA, keyA, cxA, progA;
    std::unique_ptr<BA> minorA, synthA, syncA, playA;
    std::unique_ptr<SA> bpmA;
    juce::Rectangle<int> statusArea, playerArea;
    float auroraPhase = 0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ChordPilotEditor)
};
