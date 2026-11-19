// Plain C++ tests for the desktop engine:  g++ -std=c++17 -I../Source EngineTests.cpp ../Source/Engine.cpp && ./a.out
#undef NDEBUG  // keep assert() active in Release builds
#include "Engine.h"
#include <cassert>
#include <iostream>
#include <sstream>
using namespace cp;
static std::string nm(const std::optional<Chord>& c) { return c ? c->name() : "-"; }
int main() {
    assert(genres().size() == 20); assert(pianos().size() == 10);
    for (auto& g : genres()) for (auto& p : g.progressions) {
        std::istringstream ss(p.text); int n = 0; std::string t; while (ss >> t) ++n;
        if ((int) p.chords.size() != n) { std::cerr << g.name << " " << p.text << "\n"; return 1; }
    }
    assert(nm(detect({60,64,67})) == "C"); assert(nm(detect({57,60,64})) == "Am");
    assert(nm(detect({55,59,62,65})) == "G7"); assert(nm(detect({64,67,72})) == "C/E"); assert(nm(detect({62,65,69,72})) == "Dm7");
    Engine e; e.fixedKey = Key{0,false};
    auto r = e.suggest({60,64,67}); assert(r.chords[0].chord.name() == "G");
    for (auto& s : r.chords) std::cout << s.chord.name() << "(" << s.roman << ") "; std::cout << "\n";
    Engine j; j.genre = &genres()[5]; j.fixedKey = Key{0,false};
    assert(j.suggest({50,53,57,60}).chords[0].chord.name() == "G7");
    for (auto& g : genres()) for (int cx = 0; cx < 3; ++cx) {
        Engine en; en.genre = &g; en.complexity = cx; assert(en.suggest({57,60,64}).chords.size() >= 3);
        auto p = buildPattern(g, g.defaultKey(), 0, cx); int bal[128] = {0};
        for (auto& ev : p.events) { assert(ev.step >= 0 && ev.step < p.total && ev.note >= 21 && ev.note <= 108); bal[ev.note] += ev.vel ? 1 : -1; }
        for (int b : bal) if (b) { std::cerr << g.name << " unbalanced\n"; return 1; }
    }
    std::cout << "ALL OK\n";
}
