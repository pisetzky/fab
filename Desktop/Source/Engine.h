// ChordPilot engine – C++ port of ChordPilotCore (Swift) / engine.js. No JUCE dependency.
#pragma once
#include <array>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace cp {

inline int mod12(int v) { return ((v % 12) + 12) % 12; }
extern const char* const kSharps[12];
extern const char* const kFlats[12];
extern const char* const kItalian[12];

enum class Fam { Maj, Dom, Min, Dim, Sus, Pow };

struct Quality { const char* id; std::vector<int> iv; const char* sym; Fam fam; };
const std::vector<Quality>& qualities();
int qualityIndex(const std::string& id);

struct Chord {
    int root = 0; int quality = 0; int bass = -1;
    std::set<int> pcs() const;
    std::string name(bool flats = false, bool italian = false) const;
    bool loose(const Chord& o) const;
    bool operator<(const Chord& o) const { return root != o.root ? root < o.root : quality < o.quality; }
    bool operator==(const Chord& o) const { return root == o.root && quality == o.quality && bass == o.bass; }
};
Chord makeChord(int root, int quality, int bass = -1);
std::vector<int> voicing(const Chord& c, int center, const std::vector<int>& previous = {}, bool withBass = false);
std::optional<Chord> detect(const std::vector<int>& notes);

struct Key { int tonic = 0; bool minor = false; bool operator==(const Key& o) const { return tonic == o.tonic && minor == o.minor; } };
bool prefersFlats(const Key& k);
std::optional<Key> detectKey(const std::array<double, 12>& h, double minorBias = 0);

const std::vector<int>& scaleIntervals(const std::string& type);
std::string scaleDisplayName(const std::string& type);

struct RomanChord { int offset = 0; int quality = 0; std::string symbol; };
std::optional<RomanChord> parseRoman(const std::string& text);
std::string romanLabel(const Chord& c, const Key& k);

struct Progression { std::vector<RomanChord> chords; double weight = 1; std::string text; };
struct Genre {
    std::string id, name, emoji; bool prefersMinor; int defaultTonic; double bpm;
    std::string majorScale, minorScale; std::vector<Progression> progressions; std::vector<int> signatureNotes;
    std::string chordRhythm, bassRhythm; int barsPerChord; int octave;
    Key defaultKey() const { return { defaultTonic, prefersMinor }; }
};
const std::vector<Genre>& genres();

struct PianoModel {
    std::string id, name, emoji; std::array<float, 6> partials; float B, decay, brightDecay, release, attack,
    detune, fmRatio, fmIndex, fmDecay, click, velBright, gain;
};
const std::vector<PianoModel>& pianos();

struct Highlight { int role; int rank; };  // role: 0 scale, 1 signature, 2 melody, 3 alternative, 4 primary
struct Suggestion { Chord chord; std::string roman; double score; int rank; std::vector<int> voicing; std::string reason; };
struct Result {
    std::optional<Chord> current; Key key; std::string scale; std::vector<Suggestion> chords;
    std::map<int, Highlight> highlights; std::vector<int> melody;
};

class Engine {
public:
    const Genre* genre = &genres()[0];
    int complexity = 1;                 // 0 simple, 1 genre, 2 rich
    std::optional<Key> fixedKey;
    int lowNote = 36, highNote = 96;

    Key currentKey() const;
    void reset();
    void noteOn(int note, int vel = 100);
    void commit(const Chord& c);
    void didPlay(const std::vector<int>& v, const Chord& c) { lastVoicing = v; commit(c); }
    Result suggest(const std::vector<int>& held);

private:
    std::vector<Chord> history;
    std::array<double, 12> hist {};
    std::vector<int> lastVoicing;
    std::vector<int> melodyHints(const std::vector<int>& held, const Key& k, const std::set<int>& scale, const Chord* next) const;
};

Chord adjust(const Chord& c, int complexity);
Key progressionKey(const Genre& g, const Key& k);

struct PatternEvent { int step; int note; int vel; };
struct Pattern { std::vector<PatternEvent> events; int total = 16; std::vector<Chord> chords; int stepsPerChord = 16; };
Pattern buildPattern(const Genre& g, const Key& k, int progIndex, int complexity);

} // namespace cp
