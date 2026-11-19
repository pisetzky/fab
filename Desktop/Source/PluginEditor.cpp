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
    if (b.getToggleState() && b.getProperties()["genius"]) {
        g.setGradientFill(juce::ColourGradient(green, r.getTopLeft(), cyan, r.getBottomRight(), false));
    } else if (b.getToggleState()) {
        g.setGradientFill(juce::ColourGradient(magenta, r.getTopLeft(), violet, r.getBottomRight(), false));
    } else if (b.getProperties()["song"]) {
        g.setGradientFill(juce::ColourGradient(pink.withAlpha(0.45f), r.getTopLeft(), violet.withAlpha(0.45f), r.getBottomRight(), false));
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
        if (melody.count(n)) { g.setColour(pink); g.fillRoundedRectangle(r.getX() + 4, 13, r.getWidth() - 8, 6, 3); }
        if (auto gn = geniusNext.find(n); gn != geniusNext.end()) {
            const juce::Colour gold(0xffffc233);
            g.setColour(gold); g.drawRoundedRectangle(r.reduced(1.5f), 6.0f, 3.0f);
            auto tag = juce::Rectangle<float>(r.getCentreX() - 22, black ? 14.0f : r.getBottom() - 64, 44, 16);
            g.fillRoundedRectangle(tag, 5); g.setColour(juce::Colour(0xff3a2400));
            g.setFont(juce::FontOptions(10.0f, juce::Font::bold)); g.drawText(gn->second, tag, juce::Justification::centred);
        }
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

// ---------------------------------------------------------------- Pro panel
ProPanel::ProPanel(ChordPilotProcessor& p) {
    auto setup = [this](juce::Slider& s, juce::Label& l, const char* text, const char* suffix) {
        s.setSliderStyle(juce::Slider::LinearHorizontal);
        s.setTextBoxStyle(juce::Slider::TextBoxRight, false, 64, 22);
        s.setTextValueSuffix(suffix);
        l.setText(text, juce::dontSendNotification);
        l.setColour(juce::Label::textColourId, fg);
        addAndMakeVisible(s); addAndMakeVisible(l);
    };
    setup(strum, strumL, "Strum accordi", " ms");
    setup(humanize, humanizeL, "Humanize", " %");
    setup(swing, swingL, "Swing Genre Player", " %");
    setup(transpose, transposeL, "Trasponi tastiera", "");
    for (auto* v : cp::kVoicingStyles) voicing.addItem(juce::String("Voicing: ") + v, voicing.getNumItems() + 1);
    addAndMakeVisible(oneFinger); addAndMakeVisible(scaleLock); addAndMakeVisible(voicing);
    auto& s = p.params;
    a1 = std::make_unique<BA>(s, "onefinger", oneFinger);
    a2 = std::make_unique<BA>(s, "scalelock", scaleLock);
    s1 = std::make_unique<SA>(s, "strum", strum);
    s2 = std::make_unique<SA>(s, "humanize", humanize);
    s3 = std::make_unique<SA>(s, "swing", swing);
    s4 = std::make_unique<SA>(s, "transpose", transpose);
    c1 = std::make_unique<CA>(s, "voicing", voicing);
    setSize(440, 300);
}

void ProPanel::paint(juce::Graphics& g) {
    g.fillAll(juce::Colour(0xff0d1a3a));
    g.setColour(fg); g.setFont(juce::FontOptions(18.0f, juce::Font::bold));
    g.drawText("Opzioni Pro", 16, 8, 300, 24, juce::Justification::left);
    g.setColour(muted); g.setFont(juce::FontOptions(11.0f));
    g.drawText("Ispirate a Scaler, Captain Chords, InstaChord/Cthulhu. Spente di default.", 16, 30, 420, 16, juce::Justification::left);
}

void ProPanel::resized() {
    auto r = getLocalBounds().reduced(16).withTrimmedTop(40);
    oneFinger.setBounds(r.removeFromTop(26)); scaleLock.setBounds(r.removeFromTop(26)); r.removeFromTop(6);
    for (auto [s, l] : { std::pair<juce::Slider*, juce::Label*> { &strum, &strumL }, { &humanize, &humanizeL }, { &swing, &swingL }, { &transpose, &transposeL } }) {
        auto row = r.removeFromTop(30); l->setBounds(row.removeFromLeft(150)); s->setBounds(row);
    }
    r.removeFromTop(6);
    voicing.setBounds(r.removeFromTop(30));
}

// ---------------------------------------------------------------- MIDI export
juce::File MidiDragButton::writeMidi() const {
    juce::MidiFile file; file.setTicksPerQuarterNote(480);
    auto pat = source ? source() : proc.currentPattern();
    const double bpm = proc.params.getRawParameterValue("bpm")->load();
    juce::MidiMessageSequence acc, mel;
    acc.addEvent(juce::MidiMessage::tempoMetaEvent((int) (60000000.0 / bpm)));
    if (pat) for (int loop = 0; loop < 4; ++loop) for (auto& e : pat->events) {
        int step = e.step + loop * pat->total;
        if (e.vel == 0 && e.step == 0) step = (loop + 1) * pat->total;
        const double tick = step * 120.0;
        const int ch = e.lane == 1 ? 2 : 1;
        auto m = e.vel > 0 ? juce::MidiMessage::noteOn(ch, e.note, (juce::uint8) e.vel) : juce::MidiMessage::noteOff(ch, e.note);
        m.setTimeStamp(tick);
        (e.lane == 1 ? mel : acc).addEvent(m);
    }
    acc.sort(); mel.sort();
    file.addTrack(acc); file.addTrack(mel);
    const auto& g = cp::genres()[(size_t) juce::jlimit(0, (int) cp::genres().size() - 1, proc.genreIndex())];
    auto f = juce::File::getSpecialLocation(juce::File::tempDirectory).getChildFile(fileName.isNotEmpty() ? fileName : "ChordPilot-" + juce::String(g.id) + ".mid");
    f.deleteFile();
    juce::FileOutputStream os(f);
    if (os.openedOk()) file.writeTo(os);
    return f;
}

void MidiDragButton::mouseDrag(const juce::MouseEvent& e) {
    if (dragging || e.getDistanceFromDragStart() < 8) return;
    dragging = true;
    auto f = writeMidi();
    juce::DragAndDropContainer::performExternalDragDropOfFiles({ f.getFullPathName() }, false, this, [this] { dragging = false; });
}

void MidiDragButton::clicked() {
    if (dragging) return;
    auto f = writeMidi();
    chooser = std::make_unique<juce::FileChooser>("Salva MIDI", juce::File::getSpecialLocation(juce::File::userMusicDirectory).getChildFile(f.getFileName()), "*.mid");
    chooser->launchAsync(juce::FileBrowserComponent::saveMode | juce::FileBrowserComponent::canSelectFiles,
                         [f](const juce::FileChooser& fc) { auto dest = fc.getResult(); if (dest != juce::File()) f.copyFileTo(dest); });
}

// ---------------------------------------------------------------- Inspiration
InspirePanel::InspirePanel(ChordPilotProcessor& p) : proc(p) {
    for (auto* b : { &rec4, &rec8, &fromPlayer }) addAndMakeVisible(b);
    rec4.getProperties().set("primary", true);
    status.setColour(juce::Label::textColourId, muted);
    status.setText("Fai partire la traccia nella DAW (o suona): la registrazione parte dalla prossima battuta.", juce::dontSendNotification);
    addAndMakeVisible(status);
    auto arm = [this](int bars) {
        recorded.clear(); openNotes.clear(); total = bars * 16;
        proc.inspireFifo.reset(); proc.armInspiration(bars);
        status.setText("In attesa della traccia... (" + juce::String(bars) + " battute)", juce::dontSendNotification);
    };
    rec4.onClick = [arm] { arm(4); };
    rec8.onClick = [arm] { arm(8); };
    fromPlayer.onClick = [this] {
        recorded.clear();
        if (auto pat = proc.currentPattern()) {
            total = pat->total; std::map<int, cp::PatternEvent> open;
            for (auto& e : pat->events) { int k = e.lane * 1000 + e.note;
                if (e.vel > 0) open[k] = e;
                else if (open.count(k)) { auto o = open[k]; open.erase(k); recorded.push_back({ o.step, o.note, o.vel, std::max(1, (e.step == 0 ? total : e.step) - o.step) }); } }
        }
        analyse();
    };
    setSize(560, 470);
    startTimerHz(10);
}

void InspirePanel::timerCallback() {
    int s1, n1, s2, n2; int ready = proc.inspireFifo.getNumReady();
    proc.inspireFifo.prepareToRead(ready, s1, n1, s2, n2);
    auto consume = [this](juce::int64 v) {
        bool on = (v >> 40) & 1; int note = (int) ((v >> 32) & 0x7f), vel = (int) ((v >> 24) & 0x7f), step = (int) (v & 0xffffff);
        if (on) openNotes[note] = { step, vel };
        else if (openNotes.count(note)) { auto [s, ve] = openNotes[note]; openNotes.erase(note); recorded.push_back({ s, note, ve, std::max(1, step - s) }); }
    };
    for (int i = 0; i < n1; ++i) consume(proc.inspireFifoData[(size_t) (s1 + i)]);
    for (int i = 0; i < n2; ++i) consume(proc.inspireFifoData[(size_t) (s2 + i)]);
    proc.inspireFifo.finishedRead(n1 + n2);
    int st = proc.inspireState.load();
    if (st == 2) status.setText("Registrazione in corso... " + juce::String((int) recorded.size()) + " note", juce::dontSendNotification);
    if (st == 3) {
        proc.inspireState = 0;
        for (auto& [note, sv] : openNotes) recorded.push_back({ sv.first, note, sv.second, std::max(1, total - sv.first) });
        openNotes.clear();
        if (recorded.empty()) status.setText("Nessuna nota ricevuta: manda il MIDI della traccia a ChordPilot e riprova.", juce::dontSendNotification);
        else analyse();
    }
}

void InspirePanel::analyse() {
    const auto& g = cp::genres()[(size_t) juce::jlimit(0, (int) cp::genres().size() - 1, proc.genreIndex())];
    auto r = cp::inspire(g, recorded, total);
    juce::String chords; for (auto& c : r.chords) chords << (chords.isEmpty() ? "" : " - ") << juce::String(c.name(cp::prefersFlats(r.key)));
    status.setText(juce::String("Traccia in ") + cp::kSharps[r.key.tonic] + (r.key.minor ? " minore" : " maggiore") + ", accordi " + chords,
                   juce::dontSendNotification);
    listenButtons.clear(); dragButtons.clear(); optionPatterns.clear(); names.clear();
    for (size_t i = 0; i < r.options.size(); ++i) {
        auto pat = std::make_shared<cp::Pattern>();
        pat->total = total; pat->stepsPerChord = 16; pat->chords = r.chords;
        for (auto& n : recorded) {
            int end = n.step + n.len;
            pat->events.push_back({ n.step, n.note, n.vel, 0 });
            pat->events.push_back({ end >= total ? 0 : end, n.note, 0, 0 });
        }
        pat->events.insert(pat->events.end(), r.options[i].events.begin(), r.options[i].events.end());
        std::stable_sort(pat->events.begin(), pat->events.end(), [](const cp::PatternEvent& a, const cp::PatternEvent& b) {
            if (a.step != b.step) return a.step < b.step; return (a.vel == 0) && (b.vel != 0); });
        std::shared_ptr<const cp::Pattern> cpat = pat;
        optionPatterns.push_back(cpat);
        names.add(juce::String((int) i + 1) + ". " + r.options[i].name);
        auto* listen = listenButtons.add(new juce::TextButton("Ascolta"));
        listen->onClick = [this, cpat] { proc.playCustom(cpat); };
        auto* drag = dragButtons.add(new MidiDragButton(proc));
        drag->setButtonText("Trascina MIDI");
        drag->source = [cpat] { return cpat; };
        drag->fileName = "ChordPilot-ispirazione-" + juce::String((int) i + 1) + ".mid";
        addAndMakeVisible(listen); addAndMakeVisible(drag);
    }
    resized(); repaint();
}

void InspirePanel::paint(juce::Graphics& g) {
    g.fillAll(juce::Colour(0xff0d1a3a));
    g.setColour(fg); g.setFont(juce::FontOptions(18.0f, juce::Font::bold));
    g.drawText("Ispirazione", 16, 8, 300, 24, juce::Justification::left);
    g.setFont(juce::FontOptions(13.0f, juce::Font::bold));
    for (int i = 0; i < names.size(); ++i) {
        g.setColour(fg);
        g.drawText(names[i], 16, 130 + i * 32, 230, 28, juce::Justification::centredLeft);
    }
}

void InspirePanel::resized() {
    auto r = getLocalBounds().reduced(16).withTrimmedTop(32);
    auto row = r.removeFromTop(30);
    rec4.setBounds(row.removeFromLeft(160)); row.removeFromLeft(8);
    rec8.setBounds(row.removeFromLeft(160)); row.removeFromLeft(8);
    fromPlayer.setBounds(row);
    status.setBounds(r.removeFromTop(48));
    for (int i = 0; i < listenButtons.size(); ++i) {
        listenButtons[i]->setBounds(250, 130 + i * 32, 100, 28);
        dragButtons[i]->setBounds(360, 130 + i * 32, 180, 28);
    }
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
    arpBox.addItem("Arpeggio: ritmo del genere", 1);
    for (size_t i = 0; i < cp::arpeggios().size(); ++i) arpBox.addItem(juce::String((int) i + 1) + ". " + juce::String::fromUTF8(cp::arpeggios()[i].name), (int) i + 2);
    melodyBox.addItem("Melodia: nessuna", 1);
    for (size_t i = 0; i < cp::melodyNames().size(); ++i) melodyBox.addItem("Melodia " + juce::String((int) i + 1) + ". " + juce::String::fromUTF8(cp::melodyNames()[i].c_str()), (int) i + 2);
    arpBox.getProperties().set("accent", (juce::int64) teal.getARGB());
    melodyBox.getProperties().set("accent", (juce::int64) pink.getARGB());
    newSongButton.getProperties().set("song", true);
    newSongButton.onClick = [this] { proc.newSong(); };
    proButton.onClick = [this] {
        juce::CallOutBox::launchAsynchronously(std::make_unique<ProPanel>(proc), proButton.getScreenBounds(), nullptr);
    };
    inspireButton.onClick = [this] {
        juce::CallOutBox::launchAsynchronously(std::make_unique<InspirePanel>(proc), inspireButton.getScreenBounds(), nullptr);
    };
    geniusButton.setClickingTogglesState(true);
    geniusButton.getProperties().set("genius", true);
    genreBox.getProperties().set("accent", (juce::int64) green.getARGB());
    pianoBox.getProperties().set("accent", (juce::int64) violet.getARGB());
    playButton.getProperties().set("primary", true);
    playButton.setClickingTogglesState(true);
    bpmSlider.setSliderStyle(juce::Slider::LinearHorizontal);
    bpmSlider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 64, 24);
    bpmSlider.setTextValueSuffix(" BPM");
    italianToggle.setToggleState(true, juce::dontSendNotification);

    for (juce::Component* c : std::initializer_list<juce::Component*> { &genreBox, &pianoBox, &keyBox, &complexityBox, &progressionBox,
            &minorToggle, &synthToggle, &syncToggle, &italianToggle, &playButton, &bpmSlider, &octDown, &octUp, &keyboard,
            &arpBox, &melodyBox, &newSongButton, &geniusButton, &proButton, &midiButton, &inspireButton, &drumsToggle, &handsToggle, &notesToggle })
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
    arpA = std::make_unique<CA>(s, "arp", arpBox);
    melA = std::make_unique<CA>(s, "melody", melodyBox);
    minorA = std::make_unique<BA>(s, "minor", minorToggle);
    synthA = std::make_unique<BA>(s, "synth", synthToggle);
    syncA = std::make_unique<BA>(s, "sync", syncToggle);
    playA = std::make_unique<BA>(s, "play", playButton);
    geniusA = std::make_unique<BA>(s, "genius", geniusButton);
    drumsA = std::make_unique<BA>(s, "drums", drumsToggle);
    handsA = std::make_unique<BA>(s, "hands", handsToggle);
    notesA = std::make_unique<BA>(s, "notesonly", notesToggle);
    bpmA = std::make_unique<SA>(s, "bpm", bpmSlider);
    italianToggle.onClick = [this] { keyboard.italian = italianToggle.getToggleState(); recompute(); };
    octDown.onClick = [this] { keyboard.lowest = std::max(24, keyboard.lowest - 12); recompute(); };
    octUp.onClick = [this] { keyboard.lowest = std::min(84, keyboard.lowest + 12); recompute(); };

    setResizable(true, true);
    setResizeLimits(760, 440, 2400, 1400);
    setSize(1100, 690);
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

    std::set<int> h, p, mel;
    for (int n = 0; n < 128; ++n) {
        if (proc.held[(size_t) n] > 0) h.insert(n);
        if (proc.patternNotes[(size_t) n] > 0) p.insert(n);
        if (proc.melodyNotes[(size_t) n] > 0) mel.insert(n);
    }
    if (mel != melody) { melody = mel; keyboard.melody = mel; keyboard.repaint(); }
    // Pianist mode: gold keys = suggested next notes, labelled with the chord they will produce.
    const bool geniusOn = proc.params.getRawParameterValue("genius")->load() > 0.5f;
    if (geniusOn && (proc.geniusVersion.load() != lastGeniusVersion || keyboard.geniusNext.empty())) {
        lastGeniusVersion = proc.geniusVersion.load();
        keyboard.geniusNext.clear();
        for (auto& s : proc.geniusSuggestions()) keyboard.geniusNext[s.note] = chordName(s.chord);
        keyboard.repaint();
    } else if (!geniusOn && !keyboard.geniusNext.empty()) { keyboard.geniusNext.clear(); keyboard.repaint(); }
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
    auto lg = st.withTrimmedLeft(st.getWidth() - 525).withTrimmedTop(16);
    const std::pair<juce::Colour, const char*> items[] = { { green, "Accordo migliore" }, { violet, "Alternative" }, { cyan, "Melodia" }, { magenta, "Player" }, { pink, "Melodia Player" } };
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
    drumsToggle.setBounds(second.removeFromLeft(100));
    handsToggle.setBounds(second.removeFromLeft(110));
    notesToggle.setBounds(second.removeFromLeft(110));
    r.removeFromTop(8);
    auto third = r.removeFromTop(30);
    arpBox.setBounds(third.removeFromLeft(200)); third.removeFromLeft(8);
    melodyBox.setBounds(third.removeFromLeft(220)); third.removeFromLeft(8);
    newSongButton.setBounds(third.removeFromLeft(130)); third.removeFromLeft(8);
    geniusButton.setBounds(third.removeFromLeft(130)); third.removeFromLeft(8);
    proButton.setBounds(third.removeFromLeft(56)); third.removeFromLeft(8);
    midiButton.setBounds(third.removeFromLeft(160)); third.removeFromLeft(8);
    inspireButton.setBounds(third.removeFromLeft(110));
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
