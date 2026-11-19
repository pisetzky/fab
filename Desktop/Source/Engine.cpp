#include "Engine.h"
#include <algorithm>
#include <climits>
#include <cmath>
#include <numeric>
#include <sstream>

namespace cp {

const char* const kSharps[12] = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" };
const char* const kFlats[12] = { "C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B" };
const char* const kItalian[12] = { "Do","Do#","Re","Re#","Mi","Fa","Fa#","Sol","Sol#","La","La#","Si" };

const std::vector<Quality>& qualities() {
    static const std::vector<Quality> q = {
        {"major",{0,4,7},"",Fam::Maj}, {"minor",{0,3,7},"m",Fam::Min}, {"diminished",{0,3,6},"dim",Fam::Dim},
        {"augmented",{0,4,8},"aug",Fam::Maj}, {"sus2",{0,2,7},"sus2",Fam::Sus}, {"sus4",{0,5,7},"sus4",Fam::Sus},
        {"power",{0,7},"5",Fam::Pow}, {"six",{0,4,7,9},"6",Fam::Maj}, {"minor6",{0,3,7,9},"m6",Fam::Min},
        {"dominant7",{0,4,7,10},"7",Fam::Dom}, {"major7",{0,4,7,11},"maj7",Fam::Maj}, {"minor7",{0,3,7,10},"m7",Fam::Min},
        {"halfDiminished7",{0,3,6,10},"m7b5",Fam::Dim}, {"diminished7",{0,3,6,9},"dim7",Fam::Dim},
        {"minorMajor7",{0,3,7,11},"m(maj7)",Fam::Min}, {"dominant7sus4",{0,5,7,10},"7sus4",Fam::Dom},
        {"add9",{0,4,7,14},"add9",Fam::Maj}, {"minorAdd9",{0,3,7,14},"m(add9)",Fam::Min},
        {"major9",{0,4,7,11,14},"maj9",Fam::Maj}, {"minor9",{0,3,7,10,14},"m9",Fam::Min},
        {"dominant9",{0,4,7,10,14},"9",Fam::Dom}, {"dominant7sharp9",{0,4,7,10,15},"7#9",Fam::Dom},
        {"minor11",{0,3,7,10,14,17},"m11",Fam::Min}, {"dominant13",{0,4,7,10,14,21},"13",Fam::Dom}
    };
    return q;
}

int qualityIndex(const std::string& id) {
    const auto& q = qualities();
    for (size_t i = 0; i < q.size(); ++i) if (id == q[i].id) return (int) i;
    return 0;
}

static bool famMatch(Fam a, Fam b) {
    if (a == b) return true;
    auto has = [&](Fam f) { return a == f || b == f; };
    if (has(Fam::Maj) && has(Fam::Dom)) return true;
    if (has(Fam::Pow)) return !has(Fam::Dim);
    if (has(Fam::Sus) && (has(Fam::Maj) || has(Fam::Dom))) return true;
    return false;
}

Chord makeChord(int root, int quality, int bass) {
    Chord c; c.root = mod12(root); c.quality = quality;
    c.bass = (bass < 0 || mod12(bass) == c.root) ? -1 : mod12(bass);
    return c;
}

std::set<int> Chord::pcs() const {
    std::set<int> s;
    for (int i : qualities()[quality].iv) s.insert(mod12(root + i));
    return s;
}

std::string Chord::name(bool flats, bool italian) const {
    auto names = italian ? kItalian : (flats ? kFlats : kSharps);
    std::string s = std::string(names[root]) + qualities()[quality].sym;
    if (bass >= 0) s += std::string("/") + names[bass];
    return s;
}

bool Chord::loose(const Chord& o) const {
    return root == o.root && famMatch(qualities()[quality].fam, qualities()[o.quality].fam);
}

std::vector<int> voicing(const Chord& c, int center, const std::vector<int>& previous, bool withBass) {
    std::vector<int> ints;
    for (int i : qualities()[c.quality].iv) ints.push_back(i > 12 ? i - 12 : i);
    std::vector<int> best; int bestCost = INT_MAX;
    auto floorDiv = [](int a, int b) { return (int) std::floor((double) a / b); };
    for (size_t inv = 0; inv < std::max<size_t>(1, ints.size()); ++inv) {
        for (int shift : { -12, 0, 12 }) {
            int base = floorDiv(center - 6, 12) * 12 + shift;
            std::vector<int> ordered(ints.begin() + (long) inv, ints.end());
            ordered.insert(ordered.end(), ints.begin(), ints.begin() + (long) inv);
            std::vector<int> notes; int last = INT_MIN;
            for (int iv : ordered) { int n = base + mod12(c.root + iv); while (n <= last) n += 12; notes.push_back(n); last = n; }
            if (notes.front() < 24 || notes.back() > 108) continue;
            int mid = floorDiv(notes.front() + notes.back(), 2);
            int cost = std::abs(mid - center) * 2;
            if (!previous.empty()) {
                cost = 0;
                for (int n : notes) { int m = INT_MAX; for (int p : previous) m = std::min(m, std::abs(p - n)); cost += m; }
                cost += std::abs(mid - center) / 2;
            }
            if (cost < bestCost) { bestCost = cost; best = notes; }
        }
    }
    if (withBass && !best.empty()) {
        int b = floorDiv(best[0], 12) * 12 + (c.bass >= 0 ? c.bass : c.root);
        while (b >= best[0] - 4) b -= 12;
        if (b >= 24) best.insert(best.begin(), b);
    }
    return best;
}

std::optional<Chord> detect(const std::vector<int>& notes) {
    if (notes.empty()) return std::nullopt;
    int lowest = *std::min_element(notes.begin(), notes.end());
    std::set<int> set; for (int n : notes) set.insert(mod12(n));
    if (set.size() < 2) return std::nullopt;
    int bassPC = mod12(lowest);
    std::optional<Chord> best; double bestScore = -1e9;
    const auto& qs = qualities();
    for (int root = 0; root < 12; ++root) for (size_t q = 0; q < qs.size(); ++q) {
        std::set<int> tones; for (int i : qs[q].iv) tones.insert(mod12(root + i));
        int hit = 0, extra = 0, missing = 0;
        for (int p : set) (tones.count(p) ? hit : extra)++;
        for (int t : tones) if (!set.count(t)) missing++;
        if (extra) continue;
        double score = hit * 2.0 - missing * 1.6;
        if (!set.count(root)) score -= 2.5;
        if (root == bassPC) score += 1.2;
        score -= qs[q].iv.size() * 0.05;
        if (std::string(qs[q].id) == "power" && set.size() > 2) score -= 5;
        if (score > bestScore) { bestScore = score; best = makeChord(root, (int) q, bassPC); }
    }
    if (bestScore <= 0) return std::nullopt;
    return best;
}

bool prefersFlats(const Key& k) {
    int t = k.minor ? mod12(k.tonic + 3) : k.tonic;
    return t == 5 || t == 10 || t == 3 || t == 8 || t == 1 || t == 6;
}

std::optional<Key> detectKey(const std::array<double, 12>& h, double minorBias) {
    static const double maj[12] = {6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88};
    static const double mnr[12] = {6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17};
    if (std::accumulate(h.begin(), h.end(), 0.0) <= 0) return std::nullopt;
    std::optional<Key> best; double bs = -1e9;
    for (int t = 0; t < 12; ++t) for (int minor = 0; minor < 2; ++minor) {
        const double* p = minor ? mnr : maj;
        double ma = 0, mb = 0; for (int i = 0; i < 12; ++i) { ma += h[i]; mb += p[mod12(i - t)]; }
        ma /= 12; mb /= 12;
        double n = 0, da = 0, db = 0;
        for (int i = 0; i < 12; ++i) { double a = h[i] - ma, b = p[mod12(i - t)] - mb; n += a * b; da += a * a; db += b * b; }
        double r = (da * db) == 0 ? 0 : n / std::sqrt(da * db);
        if (minor) r += minorBias;
        if (r > bs) { bs = r; best = Key { t, minor == 1 }; }
    }
    return best;
}

const std::vector<int>& scaleIntervals(const std::string& type) {
    static const std::map<std::string, std::vector<int>> s = {
        {"major",{0,2,4,5,7,9,11}}, {"naturalMinor",{0,2,3,5,7,8,10}}, {"harmonicMinor",{0,2,3,5,7,8,11}},
        {"melodicMinor",{0,2,3,5,7,9,11}}, {"dorian",{0,2,3,5,7,9,10}}, {"phrygian",{0,1,3,5,7,8,10}},
        {"lydian",{0,2,4,6,7,9,11}}, {"mixolydian",{0,2,4,5,7,9,10}}, {"locrian",{0,1,3,5,6,8,10}},
        {"majorPentatonic",{0,2,4,7,9}}, {"minorPentatonic",{0,3,5,7,10}}, {"blues",{0,3,5,6,7,10}},
        {"phrygianDominant",{0,1,4,5,7,8,10}} };
    auto it = s.find(type);
    return it == s.end() ? s.at("major") : it->second;
}

std::string scaleDisplayName(const std::string& t) {
    static const std::map<std::string, std::string> n = {
        {"major","Maggiore"}, {"naturalMinor","Minore naturale"}, {"harmonicMinor","Minore armonica"},
        {"melodicMinor","Minore melodica"}, {"dorian","Dorica"}, {"phrygian","Frigia"}, {"lydian","Lidia"},
        {"mixolydian","Misolidia"}, {"locrian","Locria"}, {"majorPentatonic","Pentatonica maggiore"},
        {"minorPentatonic","Pentatonica minore"}, {"blues","Blues"}, {"phrygianDominant","Frigia dominante"} };
    auto it = n.find(t); return it == n.end() ? t : it->second;
}

static std::set<int> scaleSet(const Key& k, const std::string& type) {
    std::set<int> s; for (int i : scaleIntervals(type)) s.insert(mod12(k.tonic + i)); return s;
}

std::optional<RomanChord> parseRoman(const std::string& text) {
    std::string s = text; int acc = 0; size_t i = 0;
    while (i < s.size() && (s[i] == 'b' || s[i] == '#')) { acc += s[i] == 'b' ? -1 : 1; ++i; }
    size_t j = i; while (j < s.size() && std::string("IViv").find(s[j]) != std::string::npos) ++j;
    if (j == i) return std::nullopt;
    std::string num = s.substr(i, j - i), suffix = s.substr(j), up = num;
    for (auto& ch : up) ch = (char) std::toupper((unsigned char) ch);
    static const std::map<std::string, int> deg = {{"I",0},{"II",2},{"III",4},{"IV",5},{"V",7},{"VI",9},{"VII",11}};
    auto d = deg.find(up); if (d == deg.end()) return std::nullopt;
    bool upper = num == up;
    static const std::map<std::string, std::pair<const char*, const char*>> suf = {
        {"",{"major","minor"}}, {"7",{"dominant7","minor7"}}, {"maj7",{"major7","minorMajor7"}}, {"9",{"dominant9","minor9"}},
        {"maj9",{"major9","major9"}}, {"6",{"six","minor6"}}, {"add9",{"add9","minorAdd9"}}, {"sus2",{"sus2","sus2"}},
        {"sus4",{"sus4","sus4"}}, {"7sus4",{"dominant7sus4","dominant7sus4"}}, {"5",{"power","power"}},
        {"dim",{"diminished","diminished"}}, {"o",{"diminished","diminished"}}, {"o7",{"diminished7","diminished7"}},
        {"dim7",{"diminished7","diminished7"}}, {"\xC3\xB8" "7",{"halfDiminished7","halfDiminished7"}},
        {"m7b5",{"halfDiminished7","halfDiminished7"}}, {"+",{"augmented","augmented"}}, {"aug",{"augmented","augmented"}},
        {"7#9",{"dominant7sharp9","dominant7sharp9"}}, {"11",{"minor11","minor11"}}, {"13",{"dominant13","dominant13"}} };
    auto q = suf.find(suffix); if (q == suf.end()) return std::nullopt;
    return RomanChord { mod12(d->second + acc), qualityIndex(upper ? q->second.first : q->second.second), text };
}

std::string romanLabel(const Chord& c, const Key& k) {
    int off = mod12(c.root - k.tonic);
    static const std::map<int, std::string> names = {{0,"I"},{2,"II"},{4,"III"},{5,"IV"},{7,"V"},{9,"VI"},{11,"VII"}};
    static const std::map<int, std::string> flat = {{1,"bII"},{3,"bIII"},{6,"bV"},{8,"bVI"},{10,"bVII"}};
    static const std::map<int, std::string> mn = {{3,"III"},{8,"VI"},{10,"VII"},{4,"#III"},{9,"#VI"},{11,"#VII"}};
    std::string n = names.count(off) ? names.at(off) : (flat.count(off) ? flat.at(off) : "?");
    if (k.minor && mn.count(off)) n = mn.at(off);
    Fam f = qualities()[c.quality].fam;
    if (f == Fam::Min || f == Fam::Dim) {
        size_t p = 0; while (p < n.size() && (n[p] == 'b' || n[p] == '#')) ++p;
        for (size_t i = p; i < n.size(); ++i) n[i] = (char) std::tolower((unsigned char) n[i]);
    }
    std::string id = qualities()[c.quality].id;
    static const std::map<std::string, std::string> sp = {{"major",""},{"minor",""},{"diminished","\xC2\xB0"},
        {"halfDiminished7","\xC3\xB8" "7"},{"diminished7","\xC2\xB0" "7"},{"augmented","+"},{"minor7","7"},{"minor6","6"},
        {"minor9","9"},{"minorAdd9","add9"},{"minorMajor7","maj7"}};
    return n + (sp.count(id) ? sp.at(id) : std::string(qualities()[c.quality].sym));
}

static Progression P(const std::string& t, double w = 1) {
    Progression p; p.text = t; p.weight = w;
    std::istringstream ss(t); std::string tok;
    while (ss >> tok) if (auto rc = parseRoman(tok)) p.chords.push_back(*rc);
    return p;
}

const std::vector<Genre>& genres() {
    static const std::vector<Genre> g = {
        {"pop","Pop","",false,0,110,"major","naturalMinor",{P("I V vi IV",3),P("vi IV I V",2),P("I vi IV V",1.5),P("IV I V vi"),P("I IV vi V"),P("I iii IV V",.7)},{2,9},"x---o---x---o---","x.......x...x...",1,60},
        {"rock","Rock","",false,9,120,"mixolydian","minorPentatonic",{P("I bVII IV I",2.5),P("I IV V IV",2),P("I V IV",1.5),P("vi IV I V"),P("I bIII IV I"),P("I5 bVII5 IV5",1.2)},{10,3},"x-o-x-o-x-o-x-o-","x-x-x-x-x-x-x-x-",1,57},
        {"hiphop","Hip-Hop","",true,2,90,"major","naturalMinor",{P("i bVI bIII bVII",2),P("i iv bVI V",1.5),P("i7 iv7",2),P("i bVII bVI V"),P("i7 bVImaj7 bIII bVII")},{3,10,8},"x-------.---o---","x.....x...x.....",1,60},
        {"trap","Trap","",true,5,140,"major","harmonicMinor",{P("i bVI iv V",2),P("i bII",1.5),P("i iv bVI V",1.5),P("i bVI bVII i"),P("i v bVI V")},{1,11,8},"x---------------","x.......x..x....",1,60},
        {"rnb","R&B","",false,3,85,"major","dorian",{P("Imaj7 vi7 ii7 V7",2),P("ii9 V13 Imaj9",2),P("IVmaj7 iii7 vi7",1.5),P("Imaj7 IVmaj7",1.5),P("IVmaj7 V7sus4 iii7 vi9")},{2,9,11},"x-----o-----o---","x.....x.....x...",1,60},
        {"jazz","Jazz","",false,10,120,"major","melodicMinor",{P("ii7 V7 Imaj7",3),P("Imaj7 vi7 ii7 V7",2),P("iii7 VI7 ii7 V7",1.5),P("ii7 bII7 Imaj7",1.2),P("Imaj7 I7 IVmaj7 iv7"),P("ii\xC3\xB8" "7 V7#9 i7")},{2,9,11,6},"..x..x.....x..x.","x...f...x...f...",1,60},
        {"blues","Blues","",false,9,95,"blues","blues",{P("I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7",3),P("I7 IV7 I7 V7",1.5),P("I7 IV7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 I7")},{3,6,10},"x--ox--ox--ox--o","x..fx..fx..fx..f",1,57},
        {"edm","EDM","",true,9,128,"major","naturalMinor",{P("i bVI bIII bVII",3),P("i bVII bVI bVII",1.5),P("bVI bVII i",1.5),P("i bIII bVII bVI")},{2,7},"x-------x-------","..x...x...x...x.",1,60},
        {"house","House","",true,7,124,"major","dorian",{P("i9 iv9",2.5),P("i7 bVIImaj7 bVImaj7 bVII",1.5),P("ii7 V7 Imaj7"),P("i7 IV7",1.5)},{9,2},"..x...x...x...x.","..x...x...x...x.",1,60},
        {"reggaeton","Reggaeton","",true,4,95,"major","naturalMinor",{P("i bVI bIII bVII",2.5),P("i bVII bVI V",1.5),P("i iv bVII bIII"),P("i bVI bVII")},{3,7},"x..x..x.x..x..x.","x..x..x.x..x..x.",1,60},
        {"latin","Latin / Bossa","",false,5,130,"major","dorian",{P("Imaj7 II7 ii7 V7",2),P("ii7 V7 Imaj7 VI7",2),P("Imaj7 bIIIo7 ii7 V7"),P("i7 iv7 V7 i7")},{2,9,11},"x..x..x...x..x..","x..fx..fx..fx..f",1,60},
        {"country","Country","",false,7,110,"majorPentatonic","naturalMinor",{P("I IV V I",3),P("I V vi IV",1.5),P("I IV I V",1.5),P("I I7 IV iv")},{2,9,3},"x.o.x.o.x.o.x.o.","x...f...x...f...",1,60},
        {"funk","Funk","",true,4,105,"mixolydian","dorian",{P("i9 IV9",3),P("i7 iv7 i7 V7#9",1.5),P("I7#9 IV9"),P("i7 bVII7 i7 IV7")},{9,10,3},"x..x..x.x.x..x..","x..x.x..x.xx..x.",1,60},
        {"gospel","Gospel / Soul","",false,8,80,"major","dorian",{P("Imaj7 iii7 vi7 ii7 V7",2),P("IV V iii vi ii V I",2),P("IVmaj7 #iv\xC3\xB8" "7 I V7"),P("I I7 IV iv",1.5),P("ii7 V7sus4 V7 Imaj9")},{2,9,10},"x-----x---x-----","x.....x...x.....",1,60},
        {"metal","Metal","",true,4,140,"mixolydian","phrygian",{P("i5 bVI5 bVII5 i5",2.5),P("i5 bII5 i5 bVII5",2),P("i bVI bIII bVII"),P("i5 iv5 bVI5 V5")},{1,6},"x.x.x.x.x.x.x.x.","x.x.x.x.x.x.x.x.",1,52},
        {"reggae","Reggae","",false,7,75,"major","dorian",{P("I IV",3),P("I V vi IV",1.5),P("I IV V IV",1.5),P("ii V")},{2,9},"..x...x...x...x.","x.....x.x.......",1,60},
        {"classical","Classica","",false,0,100,"major","harmonicMinor",{P("I IV V I",2.5),P("I vi ii V I",2),P("I IV viio iii vi ii V I",1.5),P("I V vi iii IV I IV V",1.5),P("i iv V i")},{11,2},"aaaaaaaaaaaaaaaa","x-------x-------",1,60},
        {"lofi","Lo-Fi","",false,5,80,"major","dorian",{P("ii9 V9 Imaj9",2.5),P("IVmaj7 iii7 ii7 Imaj7",2),P("Imaj7 vi9 ii9 V7sus4",1.5),P("IVmaj7 iii7 vi7 V7")},{2,9,11},"x-------..x-----","x.......x.......",1,60},
        {"afrobeats","Afrobeats","",false,1,105,"major","dorian",{P("vi IV I V",2),P("ii V I",1.5),P("I vi ii V",1.5),P("IV V vi",1.5),P("ii7 iii7 IVmaj7")},{2,9},"x..x..x...x..x..","x..x...xx.......",1,60},
        {"cinematic","Cinematic","",true,2,80,"lydian","naturalMinor",{P("i bVI bIII bVII",2),P("i bVI iv V",2),P("bVI bVII i",1.5),P("i bIII bVII IV"),P("I II IV I",.8)},{2,7},"x---------------","x---------------",2,60}
    };
    return g;
}

const std::vector<PianoModel>& pianos() {
    static const std::vector<PianoModel> p = {
        {"grand","Gran Coda da Concerto","",{1,.55f,.35f,.22f,.12f,.08f},.0004f,7,.3f,.28f,.002f,1.5f,0,0,.1f,.05f,.8f,1},
        {"bright","Pianoforte Brillante (Pop)","",{1,.72f,.52f,.38f,.25f,.16f},.0005f,5,.4f,.22f,.0015f,2,0,0,.1f,.09f,.6f,.85f},
        {"upright","Pianoforte Verticale","",{1,.6f,.32f,.26f,.1f,.05f},.0007f,4,.25f,.2f,.002f,4,0,0,.1f,.07f,.7f,1},
        {"tine","Piano Elettrico a Lamelle","",{1,.12f,.05f,0,0,0},0,3.8f,.2f,.3f,.002f,0,1,2.4f,.35f,.02f,1,1},
        {"reed","Piano Elettrico ad Ance","",{1,.5f,.42f,.16f,.1f,.04f},0,2.6f,.3f,.15f,.002f,0,1,1.1f,.25f,.03f,1,.9f},
        {"fm","Piano Elettrico FM","",{1,.2f,0,0,0,0},0,3.2f,.15f,.35f,.001f,3,14,1.6f,.08f,0,1,1},
        {"honky","Honky-Tonk","",{1,.6f,.4f,.28f,.15f,.1f},.0005f,4.2f,.35f,.2f,.002f,16,0,0,.1f,.08f,.5f,.85f},
        {"harpsichord","Clavicembalo","",{1,.9f,.8f,.7f,.6f,.5f},.0002f,2.8f,.6f,.07f,.001f,2,0,0,.1f,.22f,.1f,.6f},
        {"toy","Toy Piano","",{1,0,.6f,0,.4f,0},.02f,1.3f,.5f,.1f,.001f,0,0,0,.1f,.1f,.4f,.8f},
        {"felt","Felt Piano (Lo-Fi)","",{1,.25f,.08f,.03f,0,0},.0003f,3.5f,.3f,.5f,.009f,3,0,0,.1f,.015f,.5f,1.15f}
    };
    return p;
}

Key progressionKey(const Genre& g, const Key& k) {
    if (g.prefersMinor == k.minor) return k;
    return g.prefersMinor ? Key { mod12(k.tonic + 9), true } : Key { mod12(k.tonic + 3), false };
}

static std::string scaleFor(const Genre& g, const Key& k) { return k.minor ? g.minorScale : g.majorScale; }

Chord adjust(const Chord& c, int complexity) {
    if (complexity == 1) return c;
    std::string id = qualities()[c.quality].id;
    if (complexity == 0) {
        if (id == "augmented") return c;
        switch (qualities()[c.quality].fam) {
            case Fam::Maj: case Fam::Dom: return makeChord(c.root, qualityIndex("major"));
            case Fam::Min: return makeChord(c.root, qualityIndex("minor"));
            case Fam::Dim: return makeChord(c.root, qualityIndex("diminished"));
            default: return c;
        }
    }
    static const std::map<std::string, std::string> rich = {{"major","major7"},{"minor","minor7"},{"diminished","halfDiminished7"},
        {"dominant7","dominant9"},{"major7","major9"},{"minor7","minor9"},{"sus4","dominant7sus4"}};
    auto it = rich.find(id);
    return it == rich.end() ? c : makeChord(c.root, qualityIndex(it->second));
}

static Chord romanChord(const RomanChord& rc, const Key& k) { return makeChord(k.tonic + rc.offset, rc.quality); }

static std::vector<Chord> diatonic(const Key& k, const std::string& type, int complexity) {
    std::vector<int> ivs = scaleIntervals(type);
    if (ivs.size() != 7) ivs = scaleIntervals(k.minor ? "naturalMinor" : "major");
    std::vector<Chord> out;
    for (int d = 0; d < 7; ++d) {
        int r = ivs[d], third = mod12(ivs[(d + 2) % 7] - r), fifth = mod12(ivs[(d + 4) % 7] - r), sev = mod12(ivs[(d + 6) % 7] - r);
        std::string q = (third == 4 && fifth == 7) ? "major" : (third == 3 && fifth == 7) ? "minor" :
                        (third == 3 && fifth == 6) ? "diminished" : (third == 4 && fifth == 8) ? "augmented" : "";
        if (q.empty()) continue;
        if (complexity == 2) {
            if (q == "major") q = sev == 11 ? "major7" : sev == 10 ? "dominant7" : q;
            else if (q == "minor") q = sev == 10 ? "minor7" : sev == 11 ? "minorMajor7" : q;
            else if (q == "diminished") q = sev == 10 ? "halfDiminished7" : sev == 9 ? "diminished7" : q;
        }
        out.push_back(makeChord(k.tonic + r, qualityIndex(q)));
    }
    return out;
}

Key Engine::currentKey() const {
    if (fixedKey) return *fixedKey;
    if (std::accumulate(hist.begin(), hist.end(), 0.0) <= 2) return genre->defaultKey();
    auto k = detectKey(hist, genre->prefersMinor ? .04 : -.02);
    return k ? *k : genre->defaultKey();
}

void Engine::reset() { history.clear(); hist.fill(0); lastVoicing.clear(); }

void Engine::noteOn(int n, int v) {
    for (auto& x : hist) x *= .985;
    hist[(size_t) mod12(n)] += .5 + v / 254.0;
}

void Engine::commit(const Chord& c) {
    if (!history.empty() && history.back().loose(c)) return;
    history.push_back(c);
    if (history.size() > 8) history.erase(history.begin());
    for (int p : c.pcs()) hist[(size_t) p] += .6;
}

Result Engine::suggest(const std::vector<int>& heldIn) {
    const Genre& g = *genre;
    Key k = currentKey(), pk = progressionKey(g, k);
    std::string st = scaleFor(g, k);
    auto scale = scaleSet(k, st);
    std::vector<int> hs = heldIn; std::sort(hs.begin(), hs.end());
    auto current = detect(hs);
    std::optional<Chord> ctx = current ? current : (history.empty() ? std::nullopt : std::optional<Chord>(history.back()));

    struct Entry { Chord c; double base; };
    std::map<Chord, Entry> pool;
    for (const auto& p : g.progressions) for (const auto& rc : p.chords) {
        Chord c = adjust(romanChord(rc, pk), complexity);
        auto it = pool.find(c);
        double b = .4 * p.weight;
        if (it == pool.end()) pool[c] = { c, b }; else it->second.base = std::max(it->second.base, b);
    }
    for (const auto& c : diatonic(k, st, complexity)) if (!pool.count(c)) pool[c] = { c, .15 };

    std::optional<Chord> prior;
    if (ctx) {
        if (!history.empty() && history.back().loose(*ctx)) { if (history.size() >= 2) prior = history[history.size() - 2]; }
        else if (!history.empty()) prior = history.back();
    }
    int melody = hs.size() == 1 ? mod12(hs[0]) : -1;

    struct Scored { Chord c; double score; std::string reason; };
    std::vector<Scored> scored;
    for (const auto& [key, e] : pool) {
        const Chord& c = e.c; double score = e.base; std::string reason = "Tipico del " + g.name;
        if (ctx) {
            if (c.loose(*ctx)) score -= 3;
            for (const auto& p : g.progressions) {
                std::vector<Chord> cs; for (const auto& rc : p.chords) cs.push_back(adjust(romanChord(rc, pk), complexity));
                if (cs.size() < 2) continue;
                for (size_t i = 0; i < cs.size(); ++i) {
                    if (!cs[i].loose(*ctx)) continue;
                    if (cs[(i + 1) % cs.size()].loose(c)) {
                        score += 3 * p.weight;
                        std::string t = p.text; for (auto& ch : t) if (ch == ' ') ch = '-';
                        reason = "Progressione " + g.name + ": " + t;
                        if (prior && cs[(i + cs.size() - 1) % cs.size()].loose(*prior)) score += 1.5 * p.weight;
                    }
                }
            }
            int motion = mod12(c.root - ctx->root);
            score += motion == 5 ? .9 : motion == 7 ? .5 : (motion == 2 || motion == 10) ? .35 : (motion == 3 || motion == 4 || motion == 8 || motion == 9) ? .25 : 0;
            auto cp = c.pcs(), xp = ctx->pcs(); int common = 0; for (int p : cp) if (xp.count(p)) common++;
            score += .18 * common;
        } else if (mod12(c.root - pk.tonic) == 0) { score += 1; reason = "Accordo di tonica"; }
        if (melody >= 0) {
            if (c.pcs().count(melody)) {
                score += 2.2; if (c.root == melody) score += .4;
                reason = std::string("Armonizza la nota ") + (prefersFlats(k) ? kFlats : kSharps)[melody];
            } else score -= 1.5;
        }
        int outside = 0; for (int p : c.pcs()) if (!scale.count(p)) outside++;
        score -= .12 * outside;
        scored.push_back({ c, score, reason });
    }
    std::sort(scored.begin(), scored.end(), [](const Scored& a, const Scored& b) {
        return a.score == b.score ? a.c.name() < b.c.name() : a.score > b.score; });

    Result r; r.current = current; r.key = k; r.scale = st;
    int center = g.octave;
    if (!hs.empty()) center = std::max(48, std::min(72, std::accumulate(hs.begin(), hs.end(), 0) / (int) hs.size()));
    std::vector<int> previous = hs.size() > 1 ? hs : lastVoicing;
    for (size_t rank = 0; rank < std::min<size_t>(6, scored.size()); ++rank) {
        auto v = voicing(scored[rank].c, center, previous, false);
        if (rank == 0) previous = v;
        r.chords.push_back({ scored[rank].c, romanLabel(scored[rank].c, k), scored[rank].score, (int) rank, v, scored[rank].reason });
    }
    auto mark = [&](int n, int role, int rank) {
        if (n < lowNote || n > highNote) return;
        auto it = r.highlights.find(n);
        if (it != r.highlights.end() && it->second.role >= role) return;
        r.highlights[n] = { role, rank };
    };
    for (int n = lowNote; n <= highNote; ++n) {
        int pc = mod12(n);
        if (scale.count(pc)) {
            mark(n, 0, 99);
            for (int o : g.signatureNotes) if (mod12(k.tonic + o) == pc) mark(n, 1, 99);
        }
    }
    r.melody = melodyHints(hs, k, scale, r.chords.empty() ? nullptr : &r.chords[0].chord);
    for (int n : r.melody) mark(n, 2, 50);
    for (size_t i = 1; i < std::min<size_t>(3, r.chords.size()); ++i) for (int n : r.chords[i].voicing) mark(n, 3, (int) i);
    if (!r.chords.empty()) {
        for (int n : r.chords[0].voicing) mark(n, 4, 0);
        int low = r.chords[0].voicing.front();
        int b = (int) std::floor(low / 12.0) * 12 + r.chords[0].chord.root; while (b >= low) b -= 12;
        mark(b, 4, 0);
    }
    return r;
}

std::vector<int> Engine::melodyHints(const std::vector<int>& held, const Key& k, const std::set<int>& scale, const Chord* next) const {
    if (held.empty()) return {};
    int top = *std::max_element(held.begin(), held.end());
    std::set<int> out;
    int up = top, fu = 0; while (fu < 2 && up < top + 7) { ++up; if (scale.count(mod12(up))) { out.insert(up); ++fu; } }
    int dn = top, fd = 0; while (fd < 2 && dn > top - 7) { --dn; if (scale.count(mod12(dn))) { out.insert(dn); ++fd; } }
    if (next) for (int pc : next->pcs()) { int m = top - 5; while (mod12(m) != pc) ++m; if (m != top) out.insert(m); }
    for (int o : genre->signatureNotes) { int pc = mod12(k.tonic + o); for (int m = top - 6; m <= top + 6; ++m) if (mod12(m) == pc && m != top) out.insert(m); }
    std::vector<int> v;
    for (int n : out) if (std::find(held.begin(), held.end(), n) == held.end()) v.push_back(n);
    return v;
}

Pattern buildPattern(const Genre& g, const Key& k, int progIndex, int complexity) {
    Key pk = progressionKey(g, k);
    const auto& p = g.progressions[(size_t) std::max(0, std::min(progIndex, (int) g.progressions.size() - 1))];
    Pattern pat;
    for (const auto& rc : p.chords) pat.chords.push_back(adjust(romanChord(rc, pk), complexity));
    int spc = 16 * std::max(1, g.barsPerChord), total = spc * (int) pat.chords.size();
    pat.total = total; pat.stepsPerChord = spc;
    std::vector<int> prev;
    for (size_t ci = 0; ci < pat.chords.size(); ++ci) {
        const Chord& c = pat.chords[ci];
        auto v = voicing(c, g.octave, prev, false); prev = v;
        std::vector<int> arp = v.size() <= 1 ? std::vector<int>{0} : v.size() == 2 ? std::vector<int>{0,1} :
                               v.size() == 3 ? std::vector<int>{0,2,1,2} : std::vector<int>{0,2,1,3};
        int bass = (int) std::floor(v[0] / 12.0) * 12 + c.root; while (bass + 12 >= v[0]) bass -= 12; if (bass < 24) bass += 12;
        const auto& iv = qualities()[c.quality].iv;
        auto has = [&](int x) { return std::find(iv.begin(), iv.end(), x) != iv.end(); };
        int fifth = has(7) ? 7 : has(6) ? 6 : has(8) ? 8 : 7;
        std::vector<int> on; int bOn = -1, ai = 0;
        for (int s = 0; s < spc; ++s) {
            int step = (int) ci * spc + s; char ch = g.chordRhythm[(size_t) (s % 16)], bh = g.bassRhythm[(size_t) (s % 16)];
            if (ch == 'x' || ch == 'o') {
                for (int n : on) pat.events.push_back({ step, n, 0 });
                on = v; for (int n : v) pat.events.push_back({ step, n, ch == 'x' ? 104 : 78 });
            } else if (ch == 'a') {
                for (int n : on) pat.events.push_back({ step, n, 0 });
                int n = v[(size_t) arp[(size_t) (ai % (int) arp.size())]]; ++ai; on = { n };
                pat.events.push_back({ step, n, ai % 4 == 1 ? 92 : 72 });
            } else if (ch == '.') { for (int n : on) pat.events.push_back({ step, n, 0 }); on.clear(); }
            if (bh == 'x' || bh == 'f' || bh == 'o') {
                if (bOn >= 0) pat.events.push_back({ step, bOn, 0 });
                int n = bh == 'x' ? bass : bh == 'f' ? bass + fifth : bass + 12; bOn = n;
                pat.events.push_back({ step, n, bh == 'x' ? 100 : 84 });
            } else if (bh == '.') { if (bOn >= 0) pat.events.push_back({ step, bOn, 0 }); bOn = -1; }
        }
        int end = ((int) ci + 1) * spc, es = end == total ? 0 : end;
        for (int n : on) pat.events.push_back({ es, n, 0 });
        if (bOn >= 0) pat.events.push_back({ es, bOn, 0 });
    }
    std::stable_sort(pat.events.begin(), pat.events.end(), [](const PatternEvent& a, const PatternEvent& b) {
        if (a.step != b.step) return a.step < b.step;
        return (a.vel == 0) && (b.vel != 0); });
    return pat;
}

} // namespace cp
