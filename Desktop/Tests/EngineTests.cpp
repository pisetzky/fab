// Plain C++ tests for the desktop engine:  g++ -std=c++17 -I../Source EngineTests.cpp ../Source/Engine.cpp && ./a.out
#undef NDEBUG  // keep assert() active in Release builds
#include "Engine.h"
#include <cassert>
#include <iostream>
#include <sstream>
#include <map>
using namespace cp;
static std::string nm(const std::optional<Chord>& c) { return c ? c->name() : "-"; }
int main() {
    assert(genres().size() == 23); assert(pianos().size() == 10);
    for (auto& g : genres()) for (auto& p : g.progressions) {
        std::istringstream ss(p.text); int n = 0; std::string t; while (ss >> t) ++n;
        if ((int) p.chords.size() != n) { std::cerr << g.name << " " << p.text << "\n"; return 1; }
    }
    assert(nm(detect({60,64,67})) == "C"); assert(nm(detect({57,60,64})) == "Am");
    assert(nm(detect({55,59,62,65})) == "G7"); assert(nm(detect({64,67,72})) == "C/E"); assert(nm(detect({62,65,69,72})) == "Dm7");
    Engine e; e.fixedKey = Key{0,false};
    auto r = e.suggest({60,64,67}); assert(r.chords[0].chord.name() == "G");
    for (auto& s : r.chords) { std::cout << s.chord.name() << "(" << s.roman << ") "; }
    std::cout << "\n";
    Engine j; j.genre = &genres()[5]; // jazz j.fixedKey = Key{0,false};
    assert(j.suggest({50,53,57,60}).chords[0].chord.name() == "G7");
    for (auto& g : genres()) for (int cx = 0; cx < 3; ++cx) {
        Engine en; en.genre = &g; en.complexity = cx; assert(en.suggest({57,60,64}).chords.size() >= 3);
        auto p = buildPattern(g, g.defaultKey(), 0, cx); int bal[128] = {0};
        for (auto& ev : p.events) { assert(ev.step >= 0 && ev.step < p.total && ev.note >= 21 && ev.note <= 108); bal[ev.note] += ev.vel ? 1 : -1; }
        for (int b : bal) if (b) { std::cerr << g.name << " unbalanced\n"; return 1; }
    }
    // Arpeggios & melodies
    assert(arpeggios().size() == 30 && melodyNames().size() == 30);
    { Rng r(12345); std::cout << "rng: " << r(1000) << "," << r(1000) << "," << r(1000) << "," << r(1000) << "\n"; }
    for (auto& g : genres()) for (int arp = -1; arp < 30; arp += 3) for (int m = -1; m < 30; ++m) {
        auto p = buildPattern(g, g.defaultKey(), 0, 1, arp, m, 7);
        std::map<int, int> bal;
        for (auto& ev : p.events) { assert(ev.step >= 0 && ev.step < p.total && ev.note >= 21 && ev.note <= 108); bal[ev.lane * 1000 + ev.note] += ev.vel ? 1 : -1; }
        for (auto& [k2, b] : bal) if (b) { std::cerr << g.name << " arp " << arp << " mel " << m << " unbalanced\n"; return 1; }
    }
    for (const char* id : { "pop", "reggaeton", "jazz" }) {
        const Genre* g = nullptr; for (auto& x : genres()) if (x.id == id) g = &x;
        auto p = buildPattern(*g, g->defaultKey(), 0, 1, 0, 0, 0);
        std::cout << id; int c = 0;
        for (auto& ev : p.events) if (ev.lane == 1 && ev.vel && c++ < 14) std::cout << " " << kSharps[ev.note % 12] << (ev.note / 12 - 1) << "@" << ev.step;
        std::cout << "\n";
    }
    // Pro options
    { Engine e; e.fixedKey = Key{0,false};
      auto t = oneFingerTable(e);
      assert(makeChord(t[0].root, t[0].quality).name() == "C" && makeChord(t[9].root, t[9].quality).name() == "Am");
      int out[10]; int n = styleVoicing(t[0].tones.data(), (int) t[0].tones.size(), t[0].root, 60, 2, out);
      assert(n == 4 && out[0] == 48 && out[1] == 60 && out[2] == 67 && out[3] == 76);
      assert(lockToScale(e, 61) == 60 && lockToScale(e, 66) == 65); }
    // Genius: a new chord on every note, never repeated, pianist voicing below the melody
    { Engine e; e.fixedKey = Key{0,false}; std::optional<Chord> last; std::cout << "genius:";
      for (int n : { 61, 66, 63, 70, 68, 61, 66, 59, 64, 62 }) {
          auto g = e.genius(n); e.noteOn(g.note);
          assert(!(last && last->root == g.chord.root && last->quality == g.chord.quality));
          assert(g.chord.pcs().count(mod12(g.note)));
          std::vector<int> tones; for (int t : g.chord.pcs()) tones.push_back(t);
          int out[10]; int c = geniusVoicing(tones.data(), (int) tones.size(), g.chord.root, g.note, out);
          assert(c >= 3); for (int i = 0; i < c; ++i) assert(out[i] < g.note);
          e.commit(g.chord); last = g.chord; std::cout << " " << g.chord.name();
      }
      std::cout << "\n"; }
    // Inspiration from a recorded track (the pop genre player itself)
    { const Genre& g = genres()[0];
      auto p = buildPattern(g, Key{7,false}, 0, 1, 3, 4, 11);
      std::vector<RecordedNote> rec; std::map<int, PatternEvent> open;
      for (auto& e : p.events) { int k = e.lane * 1000 + e.note;
          if (e.vel > 0) open[k] = e; else if (open.count(k)) { auto o = open[k]; open.erase(k); rec.push_back({ o.step, o.note, o.vel, std::max(1, (e.step == 0 ? p.total : e.step) - o.step) }); } }
      auto r = inspire(g, rec, p.total);
      std::cout << "inspire key " << kSharps[r.key.tonic] << " chords:"; for (auto& c : r.chords) std::cout << " " << c.name(); std::cout << "\n";
      assert(r.options.size() == 10);
      std::set<std::string> sigs;
      for (auto& o : r.options) { std::map<int,int> bal; int ons = 0; std::string sig;
          for (auto& e : o.events) { assert(e.step >= 0 && e.step < p.total); bal[e.note] += e.vel ? 1 : -1; if (e.vel) ons++; sig += std::to_string(e.step) + ":" + std::to_string(e.note) + ","; }
          for (auto& [k2, v] : bal) assert(v == 0);
          assert(ons > 0); sigs.insert(sig); }
      assert(sigs.size() == 10); }
    // Two hands: each hand within an octave, left below the split, right above it
    { Engine e; e.fixedKey = Key{0,false};
      for (int n : { 48, 55, 53, 57, 50, 52, 59, 47 }) {
          Chord c = e.geniusLeft(n); e.commit(c);
          int lh[4]; int nl = leftHandVoicing(c.root, c.quality, n, 60, lh);
          assert(nl >= 2 && lh[nl - 1] - lh[0] <= 12); for (int i = 0; i < nl; ++i) assert(lh[i] < 60);
          std::vector<int> tones; for (int t : c.pcs()) tones.push_back(t);
          int rh[4]; int nr = rightHandVoicing(tones.data(), (int) tones.size(), c.root, 64, 60, rh);
          assert(rh[nr - 1] - rh[0] <= 12); for (int i = 0; i < nr; ++i) assert(rh[i] >= 60);
      } }
    // Melodic brain: random presses → continuous, singable melody
    for (const char* id : { "pop", "jazz", "trap" }) {
        const Genre* g = nullptr; for (auto& x : genres()) if (x.id == id) g = &x;
        Engine e; e.genre = g; e.fixedKey = g->defaultKey();
        unsigned seed = 7; double t = 0; int last = -1, steps = 0, big = 0, n = 0, homes = 0, phrases = 0;
        for (int i = 0; i < 400; ++i) {
            seed = seed * 1103515245u + 12345u; int pressed = 48 + (int) ((seed >> 8) % 36);
            seed = seed * 1103515245u + 12345u; t += 150 + (seed >> 8) % 600;
            auto r = e.genius(pressed, t); e.noteOn(r.note); e.commit(r.chord); e.geniusPlayed(r.note);
            assert(r.chord.pcs().count(mod12(r.note)));
            if (last >= 0) { ++n; int a = std::abs(r.note - last); if (a <= 2) ++steps; if (a > 9) ++big; }
            if (i % 8 == 7) { ++phrases; if (mod12(r.note) == g->defaultKey().tonic) ++homes; }
            last = r.note;
        }
        std::cout << id << ": passi " << (100 * steps / n) << "% frasi a casa " << (100 * homes / phrases) << "%\n";
        assert(big == 0 && steps * 100 / n >= 60);
    }
    std::cout << "ALL OK\n";
}
