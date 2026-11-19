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
        {"techno","Techno","",true,9,130,"mixolydian","phrygian",{P("i bII",2),P("i bVII",2),P("i iv",1.5),P("i5 bVI5",1.2)},{1,7},"x..x..x...x..x..","..xx..xx..xx..xx",2,57},
        {"melodictechno","Melodic Techno","",true,2,124,"lydian","naturalMinor",{P("i bVI bIII bVII",3),P("i bVII bVI bVII",2),P("iadd9 bVImaj7 bIIImaj7 bVII",2),P("i v bVI iv",1.5)},{2,7},"aaaaaaaaaaaaaaaa","..x...x...x...x.",2,60},
        {"afrohouse","Melodic Afro House","",true,9,122,"major","dorian",{P("i bVII bVI bVII",2.5),P("i iv bVII bIII",2),P("i7 iv7 bVIImaj7",1.5),P("i bVI bVII",1.5)},{9,2},"..x..x..x..x.x..","x..x...x..x.....",1,60},
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

Engine::GeniusChoice Engine::genius(int note) {
    Key k = currentKey();
    auto scale = scaleSet(k, scaleFor(*genre, k));
    Result ctx = suggest({});
    std::set<int> best; if (!ctx.chords.empty()) best = ctx.chords[0].chord.pcs();
    int m = note;
    for (int d : { 0, -1, 1, -2, 2 }) {
        int c = note + d;
        if (!scale.count(mod12(c))) continue;
        int twin = note - d;
        if (d != 0 && scale.count(mod12(twin)) && best.count(mod12(twin)) && !best.count(mod12(c))) { m = twin; break; }
        m = c; break;
    }
    int pc = mod12(m);
    // Every note gets its own chord: the best next chord containing the note, never the chord just played.
    const Chord* last = history.empty() ? nullptr : &history.back();
    auto fresh = [&](const Suggestion& s) { return s.chord.pcs().count(pc) && !(last && s.chord.loose(*last)); };
    std::optional<Chord> pick;
    for (auto& s : ctx.chords) if (fresh(s)) { pick = s.chord; break; }
    if (!pick) { Result r = suggest({ m }); for (auto& s : r.chords) if (fresh(s)) { pick = s.chord; break; } }
    if (!pick) for (auto& s : ctx.chords) if (s.chord.pcs().count(pc)) { pick = s.chord; break; }
    Chord ch = pick ? *pick : makeChord(k.tonic, qualityIndex(k.minor ? "minor" : "major"));
    static const std::set<std::string> rich = { "jazz", "rnb", "gospel", "lofi", "latin", "house", "melodictechno", "afrohouse", "cinematic" };
    if (rich.count(genre->id) && complexity >= 1) ch = adjust(ch, 2);
    return { m, ch, m - note };
}

DrumGroove drumGroove(const std::string& id) {
    static const std::map<std::string, DrumGroove> d = {
        {"pop",{"x.......x.x.....","....x.......x...","x.x.x.x.x.x.x.x."}}, {"rock",{"x.....x.x.......","....x.......x...","x.x.x.x.x.x.x.x."}},
        {"hiphop",{"x......x..x.....","....x.......x...","x.x.x.x.x.x.x.x."}}, {"trap",{"x.......x..x....","........x.......","x.x.xxx.x.x.x.xx"}},
        {"rnb",{"x......x..x.....","....x.......x...","x.x.x.x.x.x.x.x."}}, {"jazz",{"x.......x.......","......x.......x.","x..xx..xx..xx..x"}},
        {"blues",{"x.....x.x.....x.","....x.......x...","x..xx..xx..xx..x"}}, {"edm",{"x...x...x...x...","....x.......x...","..x...x...x...x."}},
        {"house",{"x...x...x...x...","....x.......x...","..x...x...x...x."}}, {"techno",{"x...x...x...x...","....x.......x...","xxx.xxx.xxx.xxx."}},
        {"melodictechno",{"x...x...x...x...","....x.......x...","..x...x...x...x."}}, {"afrohouse",{"x...x...x...x...","...x..x....x..x.","x.xx.xx.x.xx.xx."}},
        {"reggaeton",{"x...x...x...x...","...x..x....x..x.","x.x.x.x.x.x.x.x."}}, {"latin",{"x..x....x..x....","...x..x....x.x..","x.x.x.x.x.x.x.x."}},
        {"country",{"x.......x.......","....x.......x...","x.x.x.x.x.x.x.x."}}, {"funk",{"x..x..x...x.....","....x..x.x..x...","xxxxxxxxxxxxxxxx"}},
        {"gospel",{"x......x..x.....","....x.......x...","x.x.x.x.x.x.x.x."}}, {"metal",{"xxxxxxxxxxxxxxxx","....x.......x...","x.x.x.x.x.x.x.x."}},
        {"reggae",{"........x.......","........x.......","..x...x...x...x."}}, {"classical",{"","",""}},
        {"lofi",{"x.......x.x.....","....x.......x...","x.x.x.x.x.x.x.x."}}, {"afrobeats",{"x..x..x.x.......","....x.......x...","x.xx.xx.x.xx.xx."}},
        {"cinematic",{"x.......x.......","",""}} };
    auto it = d.find(id); return it == d.end() ? DrumGroove { "", "", "" } : it->second;
}

const char* const kVoicingStyles[5] = { "Automatico", "Stretto", "Aperto", "Drop 2", "Largo" };

std::vector<OneFingerChord> oneFingerTable(const Engine& e) {
    Key k = e.currentKey();
    auto chords = diatonic(k, scaleFor(*e.genre, k), e.complexity);
    std::vector<OneFingerChord> out;
    for (int pc = 0; pc < 12; ++pc) {
        const Chord* found = nullptr;
        for (auto& c : chords) if (c.root == pc) found = &c;
        Chord c;
        if (found) c = *found;
        else {
            int bestD = 99; Chord lower = chords.empty() ? makeChord(k.tonic, 0) : chords[0];
            for (auto& x : chords) { int d = mod12(pc - x.root); if (d <= 2 && d < bestD) { bestD = d; lower = x; } }
            c = adjust(lower, 2);
        }
        OneFingerChord o { c.root, c.quality, {} };
        for (int iv : qualities()[(size_t) c.quality].iv) {
            int t = mod12(c.root + iv);
            if (std::find(o.tones.begin(), o.tones.end(), t) == o.tones.end()) o.tones.push_back(t);
        }
        out.push_back(o);
    }
    return out;
}

int lockToScale(const Engine& e, int note) {
    Key k = e.currentKey();
    auto sc = scaleSet(k, scaleFor(*e.genre, k));
    for (int d : { 0, -1, 1, -2, 2 }) if (sc.count(mod12(note + d))) return note + d;
    return note;
}

int styleVoicing(const int* tones, int numTones, int root, int rootNote, int style, int* out) {
    int r = rootNote; while (mod12(r) != root) --r;
    int count = 0, last = r - 1;
    int order[8]; int no = 0; order[no++] = root;
    for (int i = 0; i < numTones && no < 7; ++i) if (tones[i] != root) order[no++] = tones[i];
    for (int i = 0; i < no; ++i) { int n = last + 1; while (mod12(n) != order[i]) ++n; out[count++] = n; last = n; }
    if (style == 2 && count >= 3) out[1] += 12;
    if (style == 3 && count >= 4) out[count - 2] -= 12;
    if (style == 4) for (int i = 1; i < count; ++i) out[i] += 12;
    out[count++] = r - 12;
    // keep the valid range, drop duplicates, sort
    int m = 0;
    for (int i = 0; i < count; ++i) {
        if (out[i] < 21 || out[i] > 108) continue;
        bool dup = false; for (int j = 0; j < m; ++j) dup |= out[j] == out[i];
        if (!dup) out[m++] = out[i];
    }
    std::sort(out, out + m);
    return m;
}

// Pianist voicing: right hand = up to 3 chord tones just below the melody (3rd/7th first, then 5th, 9th, root);
// left hand = root in the bass plus fifth or octave.
int geniusVoicing(const int* tones, int numTones, int root, int melody, int* out) {
    auto rank = [root](int t) { int r = mod12(t - root);
        return (r == 3 || r == 4 || r == 10 || r == 11) ? 0 : (r == 7 || r == 6 || r == 8) ? 1 : (r == 2 || r == 9 || r == 5) ? 2 : 3; };
    int ordered[6]; int no = 0;
    for (int i = 0; i < numTones && no < 6; ++i) if (tones[i] != mod12(melody)) ordered[no++] = tones[i];
    std::stable_sort(ordered, ordered + no, [&](int a, int b) { return rank(a) < rank(b); });
    no = std::min(no, 3);
    int rh[3]; int nr = 0;
    for (int i = 0; i < no; ++i) { int n = melody - 1; while (mod12(n) != ordered[i]) --n; if (n >= melody - 11) rh[nr++] = n; }
    int low = melody; for (int i = 0; i < nr; ++i) low = std::min(low, rh[i]);
    int r = std::min(low - 3, 52); while (mod12(r) != root) --r;
    if (r < 28) r += 12;
    int count = 0;
    auto add = [&](int n) { if (n < 24 || n >= melody) return; for (int j = 0; j < count; ++j) if (out[j] == n) return; out[count++] = n; };
    add(r);
    if (r + 7 < low - 2) add(r + 7); else if (r + 12 < low - 2) add(r + 12);
    for (int i = 0; i < nr; ++i) add(rh[i]);
    std::sort(out, out + count);
    return count;
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

const std::vector<Arpeggio>& arpeggios() {
    static const std::vector<Arpeggio> a = {
        {"Su","0123012301230123"}, {"Gi\xC3\xB9","3210321032103210"}, {"Su e gi\xC3\xB9","0123432101234321"},
        {"Alberti","0212021202120212"}, {"Alberti lento","0.2.1.2.0.2.1.2."}, {"Spezzato","0213021302130213"},
        {"Ottave","0303030303030303"}, {"Pedale","0102010201020102"}, {"Cascata","5432105432104321"},
        {"Salita lunga","0123456701234567"}, {"Terzine","012012012012012-"}, {"Rullo gospel","0123c---0123c---"},
        {"Stab in levare","..c...c...c...c."}, {"Trance gate","c.c.c.c.c.c.c.c."}, {"Dembow","c..c..c.c..c..c."},
        {"Charleston","c..c......c....."}, {"Bossa","0.2..1.20.2..1.2"}, {"Ballata","0---2---1---2---"},
        {"Arpa","0123456776543210"}, {"Piano pop","0-2-1-2-c---c-2-"}, {"Ostinato","0202020202020202"},
        {"Pulsante","c-c-c-c-c-c-c-c-"}, {"Sincopato","c..c..c...c.c..."}, {"Eco","0.0.2.2.1.1.3.3."},
        {"Scala di accordi","0-1-2-3-4-5-6-7-"}, {"Minimal","0-------2-------"}, {"Reggae skank","..c-..c-..c-..c-"},
        {"Funk stab","c.cc..c.c..c.c.."}, {"Rotolante","0213243546352413"}, {"Cinematico","0---1---2---3---"} };
    return a;
}

const std::vector<std::string>& melodyNames() {
    static const std::vector<std::string> n = { "Alba","Onda","Eco","Scintilla","Volo","Notte","Cometa","Respiro","Spirale","Orizzonte",
        "Ritornello","Danza","Riflesso","Sussurro","Vertigine","Marea","Lanterna","Brezza","Aurora","Galassia",
        "Fuoco","Neon","Miraggio","Tempesta","Cristallo","Satellite","Velluto","Fenice","Polvere di stelle","Eclissi" };
    return n;
}

namespace {
const char* const kRhythms[] = {
    "x-------x-------","x-----x-------..","x---x-------x---","x-------x---x---","x--x----x-------","x-----------x-x-",
    "x---x---x-x-x---","x-x---x-x---x---","x--x--x-x---x---","x---x-x---x-x---","x-x-x---x-------","..x-x-x-x---x---",
    "x--x--x---x-x---","x---x--x--x-x---",
    "x-x-x-x-x-x-x-x-","x-x-x-x-xxx-x---","x-xxx-x-x-xxx-x-","x.x.x.x.xx.xx.x.","xx-xx-x-xx-xx-x-","x-x-xx-xx-x-xx-x" };

struct GenreMelodyStyle { std::vector<std::string> rhythms; bool rep, oct, chrom, blue; int lift; int density; };

const GenreMelodyStyle& melodyStyle(const std::string& id) {
    static const std::map<std::string, GenreMelodyStyle> m = {
        {"pop", {{"x-x-x---x-x-x---","..x-x-x-x--x-x--","x--x--x-x-------","x-xx-x---x-x-x--"}, 1,1,0,0, 2, 1}},
        {"rock", {{"x---x---x-x-x---","x-x-x-x-x---x---","x--x--x-x-x-----"}, 0,0,0,1, 2, 1}},
        {"hiphop", {{"x--x--x---x-----","..x-x--x--x-x---","x-x--x--x-x-----"}, 1,0,0,1, 1, 1}},
        {"trap", {{"x--x--x--x--x-x-","x-----x-x--x----","x--x--x---------"}, 1,0,0,0, 1, 0}},
        {"rnb", {{"x-----x-x-x-----","..x---x-x--x----","x--x----x-x-x---"}, 0,0,1,0, 2, 0}},
        {"jazz", {{"x--x-x--x--x-x--","..x-x-x-x-x--x--","x-x--x-x--x-x-x-"}, 0,0,1,0, 2, 2}},
        {"blues", {{"x--x--x---x-----","..x--x-x--------","x-x--x--x-------"}, 0,0,0,1, 1, 1}},
        {"edm", {{"x-x-x-x-x--x-x--","x--x--x-x--x--x-","xx-x-x-xx-x-x---"}, 1,1,0,0, 3, 2}},
        {"house", {{"..x...x...x.x.x.","x--x--x---x-x---","..x-x-x-..x-x-x-"}, 1,0,0,0, 2, 2}},
        {"techno", {{"x-x-x-x-x-x-x-x-","x--x--x-x--x--x-","x---x---x---x---"}, 1,0,0,0, 1, 2}},
        {"melodictechno", {{"x-x-x-x-x---x---","x--x--x-x-------","x---x-x-x---x-x-"}, 1,1,0,0, 3, 1}},
        {"afrohouse", {{"x..x..x...x.x...","..x..x..x.x.....","x..x.x..x..x...."}, 1,0,1,0, 2, 1}},
        {"reggaeton", {{"x..x..x.x..x..x.","..x..x.x..x..x..","x..x..x.x-x-x---"}, 1,0,0,0, 2, 1}},
        {"latin", {{"x..x..x...x.x...","x.x..x.x..x.x...","..x.x..x.x..x..."}, 0,0,1,0, 2, 2}},
        {"country", {{"x-x-x---x-x-x---","x---x-x-x-------","..x-x-x-x---x---"}, 0,0,0,0, 2, 1}},
        {"funk", {{"x.xx.x..x.x.xx..","..x.xx.x..x.x.x.","x..x.x..xx.x...."}, 1,0,1,1, 1, 2}},
        {"gospel", {{"x-----x-x-x-----","x--x--x-x-----x-","..x-x-x-x-------"}, 0,0,1,1, 3, 0}},
        {"metal", {{"xxx-xxx-xxx-xx-x","x-x-x-x-xx-xx-x-","x-xxx-xxx-x-x---"}, 0,1,0,0, 2, 2}},
        {"reggae", {{"....x-x.....x-x.","x---..x-x---..x-","..x-x---..x-x---"}, 1,0,0,0, 1, 1}},
        {"classical", {{"x-x-x-x-x---x---","x---x-x-x-x-x---","x-xxx-x-x-------"}, 0,0,1,0, 2, 2}},
        {"lofi", {{"x-----x---x-----","..x---x-x-------","x---x-------x-x-"}, 0,0,1,0, 1, 0}},
        {"afrobeats", {{"x..x..x.x.x..x..","..x..x..x.x.x...","x..x.x..x..x.x.."}, 1,0,0,0, 2, 2}},
        {"cinematic", {{"x-------x---x---","x-----------x---","x---x---x-------"}, 0,1,0,0, 3, 0}} };
    static const GenreMelodyStyle fallback { {}, 0,0,0,0, 2, 1 };
    auto it = m.find(id); return it == m.end() ? fallback : it->second;
}

const int kContours[10][8] = { {0,1,2,3,4,3,2,1},{0,0,1,2,2,3,4,5},{5,4,4,3,2,1,1,0},{0,2,1,3,2,4,3,1},
    {0,3,1,4,2,5,1,0},{2,2,3,2,2,1,2,2},{0,2,4,2,1,3,5,3},{0,4,1,5,2,4,0,3},{4,4,4,2,3,3,3,1},{0,0,4,4,3,2,1,0} };

std::vector<std::string> rhythmPool(const GenreMelodyStyle& st) {
    std::vector<int> idx;
    if (st.density == 0) idx = { 0,1,2,3,4,5, 6,7,8,9 };
    else if (st.density == 1) idx = { 6,7,8,9,10,11,12,13, 0,1,2 };
    else idx = { 14,15,16,17,18,19, 9,10,11,12,13 };
    std::vector<std::string> pool = st.rhythms;
    pool.insert(pool.end(), st.rhythms.begin(), st.rhythms.end());
    for (int i : idx) pool.push_back(kRhythms[i]);
    return pool;
}

std::vector<PatternEvent> melodyEvents(const Genre& g, int gi, const Key& pk, const std::vector<Chord>& chords,
                                       int arp, int melody, int seed, int spc) {
    Rng R((uint32_t) ((gi + 1) * 7919u + (uint32_t) (arp + 2) * 31337u + (uint32_t) (melody + 1) * 104729u + (uint32_t) seed * 15485863u));
    const auto& st = melodyStyle(g.id);
    const std::string scaleName = scaleFor(g, pk);
    std::set<int> scale; for (int i : scaleIntervals(scaleName)) scale.insert(mod12(pk.tonic + i));
    const int center = g.octave + 10, lo = center - 9, hi = center + 14;
    std::vector<int> notes; for (int n = lo; n <= hi; ++n) if (scale.count(mod12(n))) notes.push_back(n);
    int base = 0; for (int i = 0; i < (int) notes.size(); ++i) if (std::abs(notes[(size_t) i] - (center - 3)) < std::abs(notes[(size_t) base] - (center - 3))) base = i;
    auto pool = rhythmPool(st);
    const int P = (int) pool.size();
    const std::string rA = pool[(size_t) ((melody * 3 + R(P)) % P)];
    const std::string rB = pool[(size_t) ((melody * 7 + 2 + R(P)) % P)];
    const int* cA = kContours[(melody + R(10)) % 10];
    const int* cB = kContours[(melody * 3 + 1 + R(10)) % 10];
    const int lift = st.lift, reg = R(3) - 1;
    const bool repHook = st.rep && R(3) != 0;
    std::vector<int> sig; for (int o : g.signatureNotes) sig.push_back(mod12(pk.tonic + o));
    const int blue[3] = { mod12(pk.tonic + 3), mod12(pk.tonic + 6), mod12(pk.tonic + 10) };
    const int total = spc * (int) chords.size(), N = (int) notes.size();
    auto clampIdx = [&](int i) { return std::max(0, std::min(N - 1, i)); };
    auto nearestChordTone = [&](int n, const std::set<int>& cp) {
        int best = n, bd = 99;
        for (int m : notes) if (cp.count(mod12(m)) && std::abs(m - n) < bd) { bd = std::abs(m - n); best = m; }
        return best;
    };
    auto contains = [](const auto& v, int x) { return std::find(std::begin(v), std::end(v), x) != std::end(v); };
    std::vector<PatternEvent> ev;
    int prev = -1;
    for (int b = 0; b < total / 16; ++b) {
        int ci = b * 16 / spc; auto chordPcs = chords[(size_t) ci].pcs();
        int phrase = (b / 2) % 4, inPhrase = b % 2;
        bool isB = phrase == 2; const std::string& rhythm = isB ? rB : rA; const int* contour = isB ? cB : cA;
        int shift = reg + (isB ? lift : 0) + (phrase == 1 && inPhrase == 1 ? -1 : 0);
        std::vector<int> starts; for (int s = 0; s < 16; ++s) if (rhythm[(size_t) s] == 'x') starts.push_back(s);
        for (size_t k = 0; k < starts.size(); ++k) {
            int s = starts[k], e = s + 1; while (e < 16 && rhythm[(size_t) e] == '-') ++e;
            int pos = inPhrase * 4 + s / 4;
            int idx = clampIdx(base + contour[pos] + shift);
            if (repHook && inPhrase == 0 && k > 0 && k < 3) idx = clampIdx(base + contour[0] + shift);
            int n = notes[(size_t) idx];
            if (s % 8 == 0 || k == 0) n = nearestChordTone(n, chordPcs);
            else if (st.blue && R(5) == 0) {
                for (int m : { n - 1, n + 1, n - 2 }) if (contains(blue, mod12(m)) && m >= lo && m <= hi) { n = m; break; }
            } else if (R(6) == 0) {
                std::vector<int> near; for (int m : notes) if (contains(sig, mod12(m)) && std::abs(m - n) <= 3) near.push_back(m);
                if (!near.empty()) n = near[(size_t) R((int) near.size())];
            }
            if (st.oct && isB && inPhrase == 0 && k == 0 && n + 12 <= hi + 5) n += 12;
            if (n == prev && !(repHook && inPhrase == 0) && R(2) == 0) {
                auto it = std::find(notes.begin(), notes.end(), n);
                int j = (it == notes.end() ? -1 : (int) (it - notes.begin())) + (R(2) ? 1 : -1);
                if (j >= 0 && j < N) n = notes[(size_t) j];
            }
            bool hasNext = k + 1 < starts.size(); int next = hasNext ? starts[k + 1] : -1;
            if (st.chrom && hasNext && next % 8 == 0 && e - s >= 2 && R(3) == 0) {
                int target = nearestChordTone(notes[(size_t) clampIdx(base + contour[inPhrase * 4 + next / 4] + shift)], chordPcs);
                int mid = s + std::max(1, (e - s) / 2);
                ev.push_back({ b * 16 + s, n, 92, 1 }); ev.push_back({ b * 16 + mid, n, 0, 1 });
                int ap = target - 1, stop = b * 16 + e;
                ev.push_back({ b * 16 + mid, ap, 78, 1 }); ev.push_back({ stop >= total ? 0 : stop, ap, 0, 1 });
                prev = ap; continue;
            }
            int start = b * 16 + s, stop = b * 16 + e;
            int vel = (s % 4 == 0 ? 100 : 82) + R(9) - 4;
            ev.push_back({ start, n, vel, 1 }); ev.push_back({ stop >= total ? 0 : stop, n, 0, 1 });
            prev = n;
        }
    }
    return ev;
}
} // namespace

const char* const kInspireNames[10] = { "Contrappunto", "Contrappunto II", "Armonia in terza", "Armonia in sesta", "Risposta",
    "Eco del motivo", "Hook", "Hook II", "Note guida", "Arpeggio melodico" };

InspireResult inspire(const Genre& g, const std::vector<RecordedNote>& rec, int total, std::optional<Key> fixedKey, int seed) {
    InspireResult res;
    total = std::max(16, total);
    const int bars = (total + 15) / 16;
    std::array<double, 12> hist {};
    for (auto& n : rec) hist[(size_t) mod12(n.note)] += std::max(1, n.len);
    Key key = fixedKey ? *fixedKey : detectKey(hist, g.prefersMinor ? .04 : -.02).value_or(g.defaultKey());
    const std::string st = scaleFor(g, key);
    auto scale = scaleSet(key, st);
    Key pk = progressionKey(g, key);
    auto pool = diatonic(key, st, 1);
    for (auto& p : g.progressions) for (auto& rc : p.chords) {
        Chord c = romanChord(rc, pk);
        if (std::none_of(pool.begin(), pool.end(), [&](const Chord& x) { return x.root == c.root && x.quality == c.quality; })) pool.push_back(c);
    }
    Chord prev = makeChord(key.tonic, qualityIndex(key.minor ? "minor" : "major"));
    for (int b = 0; b < bars; ++b) {
        std::array<double, 12> w {}; int low = 999; bool any = false;
        for (auto& n : rec) {
            int ov = std::min(n.step + n.len, (b + 1) * 16) - std::max(n.step, b * 16);
            if (ov > 0) { w[(size_t) mod12(n.note)] += ov; low = std::min(low, n.note); any = true; }
        }
        if (!any) { res.chords.push_back(prev); continue; }
        Chord best = prev; double bs = -1e9;
        for (auto& c : pool) {
            auto cp = c.pcs(); double sc = 0;
            for (int pc = 0; pc < 12; ++pc) sc += cp.count(pc) ? w[(size_t) pc] : -0.5 * w[(size_t) pc];
            if (low < 999 && mod12(low) == c.root) sc += 2;
            if (sc > bs) { bs = sc; best = c; }
        }
        res.chords.push_back(best); prev = best;
    }
    res.key = key;
    std::vector<const RecordedNote*> top((size_t) total, nullptr);
    std::vector<bool> onsets((size_t) total, false);
    for (auto& n : rec) if (n.step >= 0 && n.step < total) {
        onsets[(size_t) n.step] = true;
        if (!top[(size_t) n.step] || n.note > top[(size_t) n.step]->note) top[(size_t) n.step] = &n;
    }
    std::vector<int> tops; for (auto* t : top) if (t) tops.push_back(t->note);
    std::sort(tops.begin(), tops.end());
    const int median = tops.empty() ? g.octave + 7 : tops[tops.size() / 2];
    const int center = median < 60 ? median + 12 : median + 3, lo = center - 9, hi = center + 12;
    std::vector<int> notes; for (int n = lo; n <= hi; ++n) if (scale.count(mod12(n))) notes.push_back(n);
    auto nearIn = [&](int n, const std::set<int>& set) { int b = n, d = 99; for (int m : notes) if (set.count(mod12(m)) && std::abs(m - n) < d) { d = std::abs(m - n); b = m; } return b; };
    auto stepScale = [&](int n, int k) {
        int x = nearIn(n, scale); auto it = std::find(notes.begin(), notes.end(), x);
        int i = it == notes.end() ? 0 : (int) (it - notes.begin());
        i = std::max(0, std::min((int) notes.size() - 1, i + k)); return notes[(size_t) i];
    };
    auto chordAt = [&](int s) { return res.chords[(size_t) std::min((int) res.chords.size() - 1, s / 16)]; };
    struct Src { int s, note, len; }; std::vector<Src> srcLine;
    for (int s = 0; s < total; ++s) if (top[(size_t) s]) srcLine.push_back({ s, top[(size_t) s]->note, top[(size_t) s]->len });
    int gi = 0; for (size_t i = 0; i < genres().size(); ++i) if (&genres()[i] == &g) gi = (int) i;
    const auto& stl = melodyStyle(g.id); auto rpool = rhythmPool(stl); const int P = (int) rpool.size();

    for (int opt = 0; opt < 10; ++opt) {
        Rng R(((uint32_t) (gi + 1) * 7919u + (uint32_t) (42 + opt) * 31337u + (uint32_t) (opt + 1) * 104729u + (uint32_t) seed * 15485863u)
              ^ (uint32_t) (rec.size() * 2654435761u));
        struct M { int step, note, len, vel; }; std::vector<M> mel;
        auto push = [&](int step, int note, int len, int vel) {
            if (step < total && step >= 0 && note >= 21 && note <= 108) mel.push_back({ step, note, std::max(1, std::min(len, total - step)), vel }); };
        if (opt <= 1) {
            const std::string& rh = rpool[(size_t) ((R(P) + opt * 5) % P)];
            int n = nearIn(center, chordAt(0).pcs()), lastSrc = -1;
            for (int s = 0; s < total; ++s) {
                if (rh[(size_t) (s % 16)] != 'x') continue;
                if (onsets[(size_t) s] && s % 4 != 0 && R(3) != 0) continue;
                int e = s + 1; while (e < total && rh[(size_t) (e % 16)] == '-') ++e;
                auto* src = top[(size_t) s];
                if (src && lastSrc >= 0) n = stepScale(n, src->note > lastSrc ? -1 - R(2) : src->note < lastSrc ? 1 + R(2) : (R(2) ? 1 : -1));
                else n = stepScale(n, R(3) - 1);
                if (src) lastSrc = src->note;
                if (s % 8 == 0) n = nearIn(n, chordAt(s).pcs());
                if (src) { int iv = std::abs(n - src->note) % 12; if (iv == 1 || iv == 2) n = nearIn(n + 3, chordAt(s).pcs()); }
                push(s, n, e - s, s % 4 == 0 ? 96 : 82);
            }
        } else if (opt <= 3) {
            int k = opt == 2 ? 2 : 5;
            for (auto& x : srcLine) {
                int n = x.note; for (int i = 0; i < k; ++i) { ++n; while (!scale.count(mod12(n))) ++n; }
                while (n > hi + 5) n -= 12; while (n < lo) n += 12;
                push(x.s, n, x.len, 84);
            }
        } else if (opt == 4) {
            for (int w = 0; w < total; w += 8) {
                bool busy = false; for (int s = w; s < std::min(total, w + 8); ++s) busy |= onsets[(size_t) s];
                if (busy && !(w % 16 == 8 && R(2) == 0)) continue;
                bool any = false;
                for (auto& x : srcLine) if (x.s >= w - 8 && x.s < w) {
                    any = true; int off = x.s - (w - 8);
                    push(w + off, nearIn(stepScale(x.note, 2) + (x.note < lo ? 12 : 0), chordAt(w + off).pcs()), std::min(x.len, 8 - off), 86);
                }
                if (!any) { int n = nearIn(center, chordAt(w).pcs()); for (int o : { 0, 2, 4, 6 }) { push(w + o, n, 2, 84); n = stepScale(n, R(3) - 1); } }
            }
        } else if (opt == 5) {
            for (auto& x : srcLine) {
                int n = x.note + 12; while (n > hi + 5) n -= 12; while (n < lo) n += 12;
                push(x.s + 2, nearIn(n, scale), std::max(1, x.len - 1), 72);
            }
        } else if (opt <= 7) {
            auto ev = melodyEvents(g, gi, key, res.chords, -1, (opt * 7 + R(30)) % kMelodyCount, seed + opt, 16);
            for (auto& e : ev) if (e.vel > 0) {
                int len = 2;
                for (auto& o : ev) if (o.vel == 0 && o.note == e.note && (o.step > e.step || o.step == 0)) { len = (o.step == 0 ? total : o.step) - e.step; break; }
                push(e.step, e.note, len, e.vel);
            }
        } else if (opt == 8) {
            int n = center;
            for (int s = 0; s < total; s += 8) {
                const Chord& c = chordAt(s); const auto& iv = qualities()[(size_t) c.quality].iv;
                std::set<int> guide { mod12(c.root + iv[1]), mod12(c.root + (iv.size() > 3 ? iv[3] : iv[2])) };
                n = nearIn(n, guide); push(s, n, 8, 80);
            }
        } else {
            for (int s = 0; s < total; s += 2) {
                auto cp = chordAt(s).pcs();
                std::vector<int> tones; for (int m : notes) if (cp.count(mod12(m)) && m >= center - 3 && m <= center + 10) tones.push_back(m);
                if (tones.empty()) continue;
                int L = (int) tones.size(), period = std::max(1, L * 2 - 1), i = (s / 2) % period;
                int idx = i < L ? i : L * 2 - 2 - i;
                push(s, tones[(size_t) std::max(0, idx)], 2, s % 4 == 0 ? 88 : 74);
            }
        }
        std::stable_sort(mel.begin(), mel.end(), [](const M& a, const M& b) { return a.step < b.step; });
        InspireOption o; o.name = kInspireNames[opt];
        for (size_t i = 0; i < mel.size(); ++i) {
            int end = mel[i].step + mel[i].len;
            if (i + 1 < mel.size() && mel[i + 1].step < end) end = mel[i + 1].step;
            if (end <= mel[i].step) continue;
            o.events.push_back({ mel[i].step, mel[i].note, mel[i].vel, 1 });
            o.events.push_back({ end >= total ? 0 : end, mel[i].note, 0, 1 });
        }
        std::stable_sort(o.events.begin(), o.events.end(), [](const PatternEvent& a, const PatternEvent& b) {
            if (a.step != b.step) return a.step < b.step; return (a.vel == 0) && (b.vel != 0); });
        res.options.push_back(std::move(o));
    }
    return res;
}

Pattern buildPattern(const Genre& g, const Key& k, int progIndex, int complexity, int arp, int melody, int seed) {
    Key pk = progressionKey(g, k);
    const auto& p = g.progressions[(size_t) std::max(0, std::min(progIndex, (int) g.progressions.size() - 1))];
    Pattern pat;
    for (const auto& rc : p.chords) pat.chords.push_back(adjust(romanChord(rc, pk), complexity));
    int spc = 16 * std::max(1, g.barsPerChord), total = spc * (int) pat.chords.size();
    pat.total = total; pat.stepsPerChord = spc;
    const char* arpSteps = (arp >= 0 && arp < (int) arpeggios().size()) ? arpeggios()[(size_t) arp].steps : nullptr;
    std::vector<int> prev;
    for (size_t ci = 0; ci < pat.chords.size(); ++ci) {
        const Chord& c = pat.chords[ci];
        auto v = voicing(c, g.octave, prev, false); prev = v;
        std::vector<int> ext = v; for (int n : v) ext.push_back(n + 12); if (ext.size() > 8) ext.resize(8);
        std::vector<int> arpOrder = v.size() <= 1 ? std::vector<int>{0} : v.size() == 2 ? std::vector<int>{0,1} :
                                    v.size() == 3 ? std::vector<int>{0,2,1,2} : std::vector<int>{0,2,1,3};
        int bass = (int) std::floor(v[0] / 12.0) * 12 + c.root; while (bass + 12 >= v[0]) bass -= 12; if (bass < 24) bass += 12;
        const auto& iv = qualities()[c.quality].iv;
        auto has = [&](int x) { return std::find(iv.begin(), iv.end(), x) != iv.end(); };
        int fifth = has(7) ? 7 : has(6) ? 6 : has(8) ? 8 : 7;
        std::vector<int> on; int bOn = -1, ai = 0;
        auto offAll = [&](int step) { for (int n : on) pat.events.push_back({ step, n, 0, 0 }); on.clear(); };
        for (int s = 0; s < spc; ++s) {
            int step = (int) ci * spc + s; char bh = g.bassRhythm[(size_t) (s % 16)];
            if (arpSteps) {
                char ch = arpSteps[s % 16];
                if (ch == 'c') { offAll(step); on = v; for (int n : v) pat.events.push_back({ step, n, s % 4 == 0 ? 100 : 80, 0 }); }
                else if (ch >= '0' && ch <= '9') { offAll(step); int n = ext[(size_t) ((ch - '0') % (int) ext.size())]; on = { n }; pat.events.push_back({ step, n, s % 4 == 0 ? 96 : 74, 0 }); }
                else if (ch == '.') offAll(step);
            } else {
                char ch = g.chordRhythm[(size_t) (s % 16)];
                if (ch == 'x' || ch == 'o') { offAll(step); on = v; for (int n : v) pat.events.push_back({ step, n, ch == 'x' ? 104 : 78, 0 }); }
                else if (ch == 'a') { offAll(step); int n = v[(size_t) arpOrder[(size_t) (ai % (int) arpOrder.size())]]; ++ai; on = { n }; pat.events.push_back({ step, n, ai % 4 == 1 ? 92 : 72, 0 }); }
                else if (ch == '.') offAll(step);
            }
            if (bh == 'x' || bh == 'f' || bh == 'o') {
                if (bOn >= 0) pat.events.push_back({ step, bOn, 0, 0 });
                int n = bh == 'x' ? bass : bh == 'f' ? bass + fifth : bass + 12; bOn = n;
                pat.events.push_back({ step, n, bh == 'x' ? 100 : 84, 0 });
            } else if (bh == '.') { if (bOn >= 0) pat.events.push_back({ step, bOn, 0, 0 }); bOn = -1; }
        }
        int end = ((int) ci + 1) * spc, es = end == total ? 0 : end;
        offAll(es);
        if (bOn >= 0) pat.events.push_back({ es, bOn, 0, 0 });
    }
    if (melody >= 0) {
        int gi = 0; for (size_t i = 0; i < genres().size(); ++i) if (&genres()[i] == &g) gi = (int) i;
        auto m = melodyEvents(g, gi, pk, pat.chords, arp, melody % kMelodyCount, seed, spc);
        pat.events.insert(pat.events.end(), m.begin(), m.end());
    }
    std::stable_sort(pat.events.begin(), pat.events.end(), [](const PatternEvent& a, const PatternEvent& b) {
        if (a.step != b.step) return a.step < b.step;
        return (a.vel == 0) && (b.vel != 0); });
    return pat;
}

} // namespace cp
