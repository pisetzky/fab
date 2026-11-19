#include "PluginEditor.h"
#if JucePlugin_Build_Standalone
 #include <juce_audio_plugin_client/Standalone/juce_StandaloneFilterWindow.h>
#endif

using namespace aurora;

// ---------------------------------------------------------------- Look and feel
AuroraLookAndFeel::AuroraLookAndFeel() {
    setColour(juce::ComboBox::backgroundColourId, panel);
    setColour(juce::ComboBox::textColourId, fg);
    setColour(juce::ComboBox::outlineColourId, line);
    setColour(juce::ComboBox::arrowColourId, muted);
    setColour(juce::PopupMenu::backgroundColourId, juce::Colour(0xff0d1a3a));
    setColour(juce::PopupMenu::textColourId, fg);
    setColour(juce::PopupMenu::highlightedBackgroundColourId, green.withAlpha(0.25f));
    setColour(juce::PopupMenu::highlightedTextColourId, fg);
    setColour(juce::ToggleButton::textColourId, muted);
    setColour(juce::ToggleButton::tickColourId, green);
    setColour(juce::ToggleButton::tickDisabledColourId, muted);
    setColour(juce::TextButton::textColourOffId, fg);
    setColour(juce::TextButton::textColourOnId, juce::Colour(0xff022018));
    setColour(juce::Slider::textBoxTextColourId, fg);
    setColour(juce::Slider::textBoxOutlineColourId, juce::Colours::transparentBlack);
    setColour(juce::Slider::trackColourId, green);
    setColour(juce::Slider::backgroundColourId, panel);
    setColour(juce::Slider::thumbColourId, fg);
}

void AuroraLookAndFeel::drawComboBox(juce::Graphics& g, int w, int h, bool, int, int, int, int, juce::ComboBox& box) {
    auto r = juce::Rectangle<float>(0, 0, (float) w, (float) h).reduced(0.5f);
    g.setColour(panel); g.fillRoundedRectangle(r, h / 2.0f);
    auto accent = box.getProperties()["accent"];
    g.setColour(accent.isVoid() ? line : juce::Colour((juce::uint32) (juce::int64) accent).withAlpha(0.6f));
    g.drawRoundedRectangle(r, h / 2.0f, 1.2f);
    juce::Path arrow; float cx = w - 16.0f, cy = h * 0.5f;
    arrow.addTriangle(cx - 4, cy - 2, cx + 4, cy - 2, cx, cy + 3);
    g.setColour(muted); g.fillPath(arrow);
}

void AuroraLookAndFeel::drawButtonBackground(juce::Graphics& g, juce::Button& b, const juce::Colour&, bool over, bool down) {
    auto r = b.getLocalBounds().toFloat().reduced(0.5f);
    if (b.getToggleState()) {
        g.setGradientFill(juce::ColourGradient(magenta, r.getTopLeft(), violet, r.getBottomRight(), false));
    } else if (b.getProperties()["primary"]) {
        g.setGradientFill(juce::ColourGradient(green, r.getTopLeft(), teal, r.getBottomRight(), false));
    } else g.setColour(panel.brighter(over ? 0.2f : 0.0f));
    g.fillRoundedRectangle(r, r.getHeight() / 2);
    if (down) { g.setColour(juce::Colours::black.withAlpha(0.15f)); g.fillRoundedRectangle(r, r.getHeight() / 2); }
}

// ---------------------------------------------------------------- Keyboard
juce::Rectangle<float> KeyboardView::keyRect(int n) const {
    std::vector<int> whites; for (int i = lowest; i <= lowest + octaves * 12; ++i) if (!isBlack(i)) whites.push_back(i);
    float w = getWidth() / (float) whites.size(), h = (float) getHeight();
    if (!isBlack(n)) {
        auto idx = (float) (std::find(whites.begin(), whites.end(), n) - whites.begin());
        return { idx * w, 0, w, h };
    }
    auto idx = (float) (std::find(whites.begin(), whites.end(), n - 1) - whites.begin());
    float bw = w * 0.62f; int pc = cp::mod12(n);
    float shift = (pc == 1 || pc == 6) ? -0.08f : (pc == 3 || pc == 10) ? 0.08f : 0.0f;
    return { (idx + 1) * w - bw / 2 + shift * bw, 0, bw, h * 0.62f };
}

void KeyboardView::paint(juce::Graphics& g) {
    g.fillAll(juce::Colour(0xff02050d));
    auto drawKey = [&](int n) {
        bool black = isBlack(n);
        auto r = keyRect(n).reduced(black ? 0.0f : 1.0f, 0);
        juce::Colour base = black ? juce::Colour(0xff0a1022) : juce::Colour(0xffeef4ff);
        if (held.count(n)) base = base.interpolatedWith(teal, 0.35f);
        g.setColour(base); g.fillRoundedRectangle(r, black ? 5.0f : 7.0f);
        auto it = highlights.find(n);
        if (it != highlights.end()) {
            int role = it->second.role;
            juce::Colour c = role == 4 ? green : role == 3 ? violet : role == 2 ? cyan : juce::Colours::transparentBlack;
            float a = role == 4 ? 0.95f : role == 3 ? (it->second.rank == 1 ? 0.65f : 0.45f) : role == 2 ? 0.55f : 0.0f;
            if (a > 0) {
                g.setGradientFill(juce::ColourGradient(c.withAlpha(a * 0.2f), r.getX(), r.getY(), c.withAlpha(a), r.getX(), r.getBottom(), false));
                g.fillRoundedRectangle(r, black ? 5.0f : 7.0f);
            }
            if (showScale && (role == 0 || role == 1)) {
                float d = std::min(r.getWidth() * 0.28f, 8.0f);
                auto dot = juce::Rectangle<float>(r.getCentreX() - d / 2, r.getBottom() - d - 10, d, d);
                g.setColour(role == 1 ? green : (black ? juce::Colour(0xff5a6c94) : juce::Colour(0xff8ea2c8)));
                if (role == 1) { juce::Path p; p.addRectangle(dot); g.fillPath(p, juce::AffineTransform::rotation(0.785f, dot.getCentreX(), dot.getCentreY())); }
                else g.fillEllipse(dot);
            }
        }
        if (pattern.count(n)) { g.setColour(magenta); g.fillRoundedRectangle(r.getX() + 4, 5, r.getWidth() - 8, 6, 3); }
        if (held.count(n)) { g.setColour(teal); g.drawRoundedRectangle(r.reduced(1.5f), 6.0f, 3.0f); }
        bool primary = it != highlights.end() && it->second.role == 4;
        if (cp::mod12(n) == 0 || primary || held.count(n)) {
            juce::String lbl = italian ? cp::kItalian[cp::mod12(n)] : (flats ? cp::kFlats[cp::mod12(n)] : cp::kSharps[cp::mod12(n)]);
            if (cp::mod12(n) == 0) lbl << (n / 12 - 1);
            g.setColour(primary ? juce::Colour(0xff022018) : (black ? juce::Colour(0xffc9d6f5) : juce::Colour(0xff3a4a6b)));
            g.setFont(juce::FontOptions(black ? 10.0f : 12.0f, juce::Font::bold));
            g.drawText(lbl, r.withTrimmedBottom(22).removeFromBottom(16), juce::Justification::centred);
        }
    };
    for (int n = lowest; n <= lowest + octaves * 12; ++n) if (!isBlack(n)) drawKey(n);
    for (int n = lowest; n <= lowest + octaves * 12; ++n) if (isBlack(n)) drawKey(n);
}

int KeyboardView::noteAt(juce::Point<float> p, int& velocity) const {
    for (int pass = 0; pass < 2; ++pass)
        for (int n = lowest; n <= lowest + octaves * 12; ++n) {
            if (isBlack(n) != (pass == 0)) continue;
            auto r = keyRect(n);
            if (r.contains(p)) { velocity = 45 + (int) (juce::jlimit(0.0f, 1.0f, (p.y - r.getY()) / r.getHeight()) * 82); return n; }
        }
    return -1;
}

void KeyboardView::mouseDown(const juce::MouseEvent& e) {
    int v = 0, n = noteAt(e.position, v);
    touches[e.source.getIndex()] = n;
    if (n >= 0) proc.keyboardState.noteOn(1, n, v / 127.0f);
}

void KeyboardView::mouseDrag(const juce::MouseEvent& e) {
    int v = 0, n = noteAt(e.position, v), idx = e.source.getIndex();
    int cur = touches.count(idx) ? touches[idx] : -1;
    if (n == cur) return;
    if (cur >= 0) proc.keyboardState.noteOff(1, cur, 0);
    touches[idx] = n;
    if (n >= 0) proc.keyboardState.noteOn(1, n, v / 127.0f);
}

void KeyboardView::mouseUp(const juce::MouseEvent& e) {
    int idx = e.source.getIndex();
    if (touches.count(idx) && touches[idx] >= 0) proc.keyboardState.noteOff(1, touches[idx], 0);
    touches.erase(idx);
}

// ---------------------------------------------------------------- Cards
void SuggestionCard::paint(juce::Graphics& g) {
    if (!valid) return;
    auto r = getLocalBounds().toFloat().reduced(1.5f);
    bool best = s.rank == 0;
    juce::Colour tint = best ? green : violet;
    g.setGradientFill(juce::ColourGradient(tint.withAlpha(best ? 0.3f : 0.16f), r.getTopLeft(), juce::Colours::white.withAlpha(0.03f), r.getBottomRight(), false));
    g.fillRoundedRectangle(r, 14);
    g.setColour(tint.withAlpha(best ? 0.95f : 0.4f)); g.drawRoundedRectangle(r, 14, best ? 2.0f : 1.0f);
    auto in = r.reduced(10, 8);
    g.setFont(juce::FontOptions(10.0f, juce::Font::bold)); g.setColour(tint);
    g.drawText(best ? "PROSSIMO" : "#" + juce::String(s.rank + 1), in.removeFromTop(14), juce::Justification::left);
    g.setColour(muted);
    g.drawText(juce::String::fromUTF8(s.roman.c_str()), in.withHeight(14).translated(0, -14), juce::Justification::right);
    g.setColour(fg); g.setFont(juce::FontOptions(24.0f, juce::Font::bold));
    g.drawFittedText(name, in.removeFromTop(30).toNearestInt(), juce::Justification::left, 1);
    g.setColour(muted); g.setFont(juce::FontOptions(11.0f));
    g.drawFittedText(juce::String::fromUTF8(s.reason.c_str()), in.toNearestInt(), juce::Justification::topLeft, 2);
}

// ---------------------------------------------------------------- Editor
ChordPilotEditor::ChordPilotEditor(ChordPilotProcessor& p) : AudioProcessorEditor(p), proc(p), keyboard(p) {
    setLookAndFeel(&lnf);
    juce::StringArray gn, pn, kn { "Tonalita: Auto" }, cx { "Semplici", "Del genere", "Ricchi" };
    for (auto& g : cp::genres()) gn.add(g.name);
    for (auto& m : cp::pianos()) pn.add(m.name);
    for (int i = 0; i < 12; ++i) kn.add(juce::String(cp::kItalian[i]) + " / " + cp::kSharps[i]);
    genreBox.addItemList(gn, 1); pianoBox.addItemList(pn, 1); keyBox.addItemList(kn, 1); complexityBox.addItemList(cx, 1);
    for (int i = 0; i < 6; ++i) progressionBox.addItem("Progressione " + juce::String(i + 1), i + 1);
    genreBox.getProperties().set("accent", (juce::int64) green.getARGB());
    pianoBox.getProperties().set("accent", (juce::int64) violet.getARGB());
    playButton.getProperties().set("primary", true);
    playButton.setClickingTogglesState(true);
    bpmSlider.setSliderStyle(juce::Slider::LinearHorizontal);
    bpmSlider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 64, 24);
    bpmSlider.setTextValueSuffix(" BPM");
    italianToggle.setToggleState(true, juce::dontSendNotification);

    for (juce::Component* c : std::initializer_list<juce::Component*> { &genreBox, &pianoBox, &keyBox, &complexityBox, &progressionBox,
            &minorToggle, &synthToggle, &syncToggle, &italianToggle, &playButton, &bpmSlider, &octDown, &octUp, &keyboard })
        addAndMakeVisible(c);
    for (auto& c : cards) {
        addAndMakeVisible(c);
        c.onTap = [this, &c] {
            auto notes = c.s.voicing;
            int b = (notes.front() / 12) * 12 + c.s.chord.root; while (b >= notes.front()) b -= 12;
            if (b >= 24) notes.insert(notes.begin(), b);
            proc.playChord(notes, true);
            juce::Timer::callAfterDelay(900, [p = &proc, notes] { p->playChord(notes, false); });
            engine.didPlay(c.s.voicing, c.s.chord); lastCommitted = c.s.chord;
            recompute();
        };
    }
    auto& s = proc.params;
    genreA = std::make_unique<CA>(s, "genre", genreBox);
    pianoA = std::make_unique<CA>(s, "piano", pianoBox);
    keyA = std::make_unique<CA>(s, "key", keyBox);
    cxA = std::make_unique<CA>(s, "complexity", complexityBox);
    progA = std::make_unique<CA>(s, "progression", progressionBox);
    minorA = std::make_unique<BA>(s, "minor", minorToggle);
    synthA = std::make_unique<BA>(s, "synth", synthToggle);
    syncA = std::make_unique<BA>(s, "sync", syncToggle);
    playA = std::make_unique<BA>(s, "play", playButton);
    bpmA = std::make_unique<SA>(s, "bpm", bpmSlider);
    italianToggle.onClick = [this] { keyboard.italian = italianToggle.getToggleState(); recompute(); };
    octDown.onClick = [this] { keyboard.lowest = std::max(24, keyboard.lowest - 12); recompute(); };
    octUp.onClick = [this] { keyboard.lowest = std::min(84, keyboard.lowest + 12); recompute(); };

    setResizable(true, true);
    setResizeLimits(760, 440, 2400, 1400);
    setSize(1100, 640);
    syncEngine(); recompute();
    startTimerHz(30);
}

ChordPilotEditor::~ChordPilotEditor() { stopTimer(); setLookAndFeel(nullptr); }

void ChordPilotEditor::syncEngine() {
    const auto& gs = cp::genres();
    const cp::Genre* g = &gs[(size_t) juce::jlimit(0, (int) gs.size() - 1, proc.genreIndex())];
    if (g != engine.genre) { engine.genre = g; engine.reset(); lastCommitted.reset(); }
    engine.complexity = (int) proc.params.getRawParameterValue("complexity")->load();
    int k = (int) proc.params.getRawParameterValue("key")->load();
    bool minor = proc.params.getRawParameterValue("minor")->load() > 0.5f;
    engine.fixedKey = k == 0 ? std::nullopt : std::optional<cp::Key>(cp::Key { k - 1, minor });
}

juce::String ChordPilotEditor::chordName(const cp::Chord& c) const {
    return juce::String::fromUTF8(c.name(cp::prefersFlats(result.key), keyboard.italian).c_str());
}

void ChordPilotEditor::recompute() {
    engine.lowNote = keyboard.lowest; engine.highNote = keyboard.lowest + keyboard.octaves * 12;
    result = engine.suggest(std::vector<int>(held.begin(), held.end()));
    keyboard.highlights = result.highlights; keyboard.held = held; keyboard.pattern = pattern;
    keyboard.flats = cp::prefersFlats(result.key); keyboard.repaint();
    for (size_t i = 0; i < cards.size(); ++i) {
        cards[i].valid = i < result.chords.size();
        if (cards[i].valid) { cards[i].s = result.chords[i]; cards[i].name = chordName(result.chords[i].chord); }
        cards[i].repaint();
    }
    repaint(statusArea); repaint(playerArea);
}

void ChordPilotEditor::autoConnectStandaloneMidi() {
#if JucePlugin_Build_Standalone
    if (!juce::JUCEApplicationBase::isStandaloneApp()) return;
    if (auto* holder = juce::StandalonePluginHolder::getInstance()) {
        auto& dm = holder->deviceManager;
        // Every MIDI keyboard that appears is enabled automatically – no MIDI setup needed.
        for (auto& d : juce::MidiInput::getAvailableDevices())
            if (!dm.isMidiInputDeviceEnabled(d.identifier)) dm.setMidiInputDeviceEnabled(d.identifier, true);
        auto outs = juce::MidiOutput::getAvailableDevices();
        if (dm.getDefaultMidiOutputIdentifier().isEmpty() && !outs.isEmpty()) dm.setDefaultMidiOutputDevice(outs[0].identifier);
    }
#endif
}

void ChordPilotEditor::timerCallback() {
    ++tick;
    if (tick % 60 == 1) autoConnectStandaloneMidi();
    syncEngine();
    int s1, n1, s2, n2;
    int ready = proc.noteFifo.getNumReady();
    proc.noteFifo.prepareToRead(ready, s1, n1, s2, n2);
    for (int i = 0; i < n1; ++i) { int v = proc.noteFifoData[(size_t) (s1 + i)]; engine.noteOn(v & 0x7f, (v >> 8) & 0x7f); }
    for (int i = 0; i < n2; ++i) { int v = proc.noteFifoData[(size_t) (s2 + i)]; engine.noteOn(v & 0x7f, (v >> 8) & 0x7f); }
    proc.noteFifo.finishedRead(n1 + n2);

    std::set<int> h, p;
    for (int n = 0; n < 128; ++n) { if (proc.held[(size_t) n] > 0) h.insert(n); if (proc.patternNotes[(size_t) n] > 0) p.insert(n); }
    bool changed = false;
    if (h != held) { held = h; heldChangedAt = juce::Time::getMillisecondCounter(); changed = true; }
    else if (heldChangedAt && juce::Time::getMillisecondCounter() - heldChangedAt > 250) {
        heldChangedAt = 0;
        if (result.current && !(lastCommitted && lastCommitted->loose(*result.current))) {
            engine.commit(*result.current); lastCommitted = result.current; changed = true;
        }
    }
    if (p != pattern) { pattern = p; keyboard.pattern = p; keyboard.repaint(); repaint(playerArea); }
    if ((int) proc.params.getRawParameterValue("key")->load() == 0) {
        auto k = engine.currentKey(); proc.detectedKeyCode = k.tonic + (k.minor ? 12 : 0);
    }
    if (changed || tick % 15 == 0) recompute();
    auroraPhase += 0.01f;
    if (tick % 3 == 0) repaint(getLocalBounds().withHeight(130));
}

void ChordPilotEditor::paint(juce::Graphics& g) {
    auto b = getLocalBounds().toFloat();
    g.setGradientFill(juce::ColourGradient(night, 0, 0, deep, 0, b.getHeight(), false)); g.fillAll();
    // Aurora curtains
    const juce::Colour bands[] = { green, teal, violet, magenta };
    for (int k = 0; k < 4; ++k)
        for (int i = 0; i < 24; ++i) {
            float x = b.getWidth() * i / 23.0f;
            float wave = std::sin(auroraPhase + i * 0.45f + k * 1.6f) * 0.05f + std::sin(auroraPhase * 1.7f + i * 0.9f + k) * 0.03f;
            float y = b.getHeight() * (0.12f + k * 0.05f + wave), hh = b.getHeight() * 0.22f;
            g.setGradientFill(juce::ColourGradient(bands[k].withAlpha(0.0f), x, y - hh, bands[k].withAlpha(0.10f - k * 0.015f), x, y, false));
            g.fillRect(x - b.getWidth() / 40, y - hh, b.getWidth() / 18, hh * 1.1f);
        }
    // Status
    auto st = statusArea.toFloat();
    g.setColour(muted); g.setFont(juce::FontOptions(10.0f, juce::Font::bold));
    g.drawText("STAI SUONANDO", st.withHeight(14), juce::Justification::left);
    juce::String now = result.current ? chordName(*result.current) : juce::String("-");
    if (!result.current && !held.empty()) { now.clear(); for (int n : held) now << (keyboard.italian ? cp::kItalian[cp::mod12(n)] : cp::kSharps[cp::mod12(n)]) << " "; }
    g.setColour(fg); g.setFont(juce::FontOptions(30.0f, juce::Font::bold));
    g.drawText(now, st.withTrimmedTop(14).withWidth(220), juce::Justification::centredLeft);
    g.setColour(green); g.setFont(juce::FontOptions(22.0f));
    g.drawText(juce::String::fromUTF8("\xE2\x86\x92"), st.withX(st.getX() + 220).withWidth(30).withTrimmedTop(14), juce::Justification::centredLeft);
    g.setColour(muted); g.setFont(juce::FontOptions(10.0f, juce::Font::bold));
    g.drawText("SCALA", st.withX(st.getX() + 260).withHeight(14), juce::Justification::left);
    g.setColour(fg); g.setFont(juce::FontOptions(15.0f, juce::Font::bold));
    juce::String scale = juce::String(keyboard.italian ? cp::kItalian[result.key.tonic] : (cp::prefersFlats(result.key) ? cp::kFlats : cp::kSharps)[result.key.tonic])
        + " " + juce::String(cp::scaleDisplayName(result.scale)) + (engine.fixedKey ? "" : " - auto");
    g.drawText(scale, st.withX(st.getX() + 260).withTrimmedTop(14), juce::Justification::centredLeft);
    // Legend
    auto lg = st.withTrimmedLeft(st.getWidth() - 420).withTrimmedTop(16);
    const std::pair<juce::Colour, const char*> items[] = { { green, "Accordo migliore" }, { violet, "Alternative" }, { cyan, "Melodia" }, { magenta, "Genre Player" } };
    g.setFont(juce::FontOptions(12.0f));
    for (auto& [c, t] : items) {
        g.setColour(c); g.fillRoundedRectangle(lg.getX(), lg.getCentreY() - 5, 10, 10, 3);
        g.setColour(muted); g.drawText(t, lg.withTrimmedLeft(14).withWidth(100), juce::Justification::centredLeft);
        lg.removeFromLeft(105);
    }
    // Genre player strip
    auto pl = playerArea.toFloat();
    g.setColour(muted); g.setFont(juce::FontOptions(10.0f, juce::Font::bold));
    g.drawText("GENRE PLAYER", pl.removeFromLeft(96), juce::Justification::centredLeft);
    if (auto pat = proc.currentPattern()) {
        bool playing = proc.params.getRawParameterValue("play")->load() > 0.5f;
        int active = proc.patternChordIndex.load() % std::max(1, (int) pat->chords.size());
        g.setFont(juce::FontOptions(13.0f, juce::Font::bold));
        for (size_t i = 0; i < pat->chords.size() && pl.getWidth() > 60; ++i) {
            auto txt = chordName(pat->chords[i]);
            float w = juce::GlyphArrangement::getStringWidth(g.getCurrentFont(), txt) + 22;
            auto pill = pl.removeFromLeft(w).reduced(0, 3); pl.removeFromLeft(6);
            bool on = playing && (int) i == active;
            g.setColour(on ? magenta : juce::Colours::white.withAlpha(0.07f)); g.fillRoundedRectangle(pill, pill.getHeight() / 2);
            g.setColour(on ? juce::Colours::white : fg.withAlpha(0.85f)); g.drawText(txt, pill, juce::Justification::centred);
        }
    }
}

void ChordPilotEditor::resized() {
    auto r = getLocalBounds().reduced(16, 12);
    auto top = r.removeFromTop(36);
    genreBox.setBounds(top.removeFromLeft(170)); top.removeFromLeft(8);
    pianoBox.setBounds(top.removeFromLeft(230)); top.removeFromLeft(8);
    keyBox.setBounds(top.removeFromLeft(160)); top.removeFromLeft(6);
    minorToggle.setBounds(top.removeFromLeft(84)); top.removeFromLeft(6);
    complexityBox.setBounds(top.removeFromLeft(130));
    playButton.setBounds(top.removeFromRight(130));
    r.removeFromTop(8);
    auto second = r.removeFromTop(30);
    bpmSlider.setBounds(second.removeFromLeft(260)); second.removeFromLeft(10);
    progressionBox.setBounds(second.removeFromLeft(150)); second.removeFromLeft(10);
    synthToggle.setBounds(second.removeFromLeft(120));
    syncToggle.setBounds(second.removeFromLeft(100));
    italianToggle.setBounds(second.removeFromLeft(100));
    r.removeFromTop(8);
    statusArea = r.removeFromTop(48);
    r.removeFromTop(6);
    auto cardRow = r.removeFromTop(juce::jlimit(70, 104, getHeight() / 6));
    int cw = std::min(160, (cardRow.getWidth() - 50) / 6);
    for (auto& c : cards) { c.setBounds(cardRow.removeFromLeft(cw)); cardRow.removeFromLeft(10); }
    r.removeFromTop(6);
    playerArea = r.removeFromTop(28);
    r.removeFromTop(8);
    octDown.setBounds(r.removeFromLeft(32)); r.removeFromLeft(6);
    octUp.setBounds(r.removeFromRight(32)); r.removeFromRight(6);
    keyboard.setBounds(r);
}
