// ChordPilot engine (JavaScript port of ChordPilotCore). Pure functions, no DOM.
const CP = (() => {
  const mod12 = v => ((v % 12) + 12) % 12;
  const SHARPS = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
  const FLATS = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"];
  const ITALIAN = ["Do","Do#","Re","Re#","Mi","Fa","Fa#","Sol","Sol#","La","La#","Si"];

  const Q = {
    major:{iv:[0,4,7],sym:"",fam:"maj"}, minor:{iv:[0,3,7],sym:"m",fam:"min"},
    diminished:{iv:[0,3,6],sym:"dim",fam:"dim"}, augmented:{iv:[0,4,8],sym:"aug",fam:"maj"},
    sus2:{iv:[0,2,7],sym:"sus2",fam:"sus"}, sus4:{iv:[0,5,7],sym:"sus4",fam:"sus"}, power:{iv:[0,7],sym:"5",fam:"pow"},
    six:{iv:[0,4,7,9],sym:"6",fam:"maj"}, minor6:{iv:[0,3,7,9],sym:"m6",fam:"min"},
    dominant7:{iv:[0,4,7,10],sym:"7",fam:"dom"}, major7:{iv:[0,4,7,11],sym:"maj7",fam:"maj"},
    minor7:{iv:[0,3,7,10],sym:"m7",fam:"min"}, halfDiminished7:{iv:[0,3,6,10],sym:"m7b5",fam:"dim"},
    diminished7:{iv:[0,3,6,9],sym:"dim7",fam:"dim"}, minorMajor7:{iv:[0,3,7,11],sym:"m(maj7)",fam:"min"},
    dominant7sus4:{iv:[0,5,7,10],sym:"7sus4",fam:"dom"}, add9:{iv:[0,4,7,14],sym:"add9",fam:"maj"},
    minorAdd9:{iv:[0,3,7,14],sym:"m(add9)",fam:"min"}, major9:{iv:[0,4,7,11,14],sym:"maj9",fam:"maj"},
    minor9:{iv:[0,3,7,10,14],sym:"m9",fam:"min"}, dominant9:{iv:[0,4,7,10,14],sym:"9",fam:"dom"},
    dominant7sharp9:{iv:[0,4,7,10,15],sym:"7#9",fam:"dom"}, minor11:{iv:[0,3,7,10,14,17],sym:"m11",fam:"min"},
    dominant13:{iv:[0,4,7,10,14,21],sym:"13",fam:"dom"}
  };
  const QNAMES = Object.keys(Q);

  function famMatch(a, b) {
    if (a === b) return true;
    const s = new Set([a, b]);
    if (s.has("maj") && s.has("dom")) return true;
    if (a === "pow" || b === "pow") return a !== "dim" && b !== "dim";
    if (s.has("sus") && (s.has("maj") || s.has("dom"))) return true;
    return false;
  }

  function chord(root, quality, bass = null) {
    root = mod12(root);
    if (bass !== null && mod12(bass) === root) bass = null;
    return { root, quality, bass: bass === null ? null : mod12(bass) };
  }
  const pcs = c => new Set(Q[c.quality].iv.map(i => mod12(c.root + i)));
  const chordName = (c, flats = false, names = null) => {
    const n = names || (flats ? FLATS : SHARPS);
    return n[c.root] + Q[c.quality].sym + (c.bass !== null ? "/" + n[c.bass] : "");
  };
  const loose = (a, b) => a.root === b.root && famMatch(Q[a.quality].fam, Q[b.quality].fam);
  const key = (c) => c.root + ":" + c.quality;

  function voicing(c, center, previous = [], withBass = false) {
    const ints = Q[c.quality].iv.map(i => i > 12 ? i - 12 : i);
    let best = [], bestCost = Infinity;
    for (let inv = 0; inv < Math.max(1, ints.length); inv++) {
      for (const shift of [-12, 0, 12]) {
        const base = Math.floor((center - 6) / 12) * 12 + shift;
        const ordered = ints.slice(inv).concat(ints.slice(0, inv));
        const notes = []; let last = -Infinity;
        for (const iv of ordered) { let n = base + mod12(c.root + iv); while (n <= last) n += 12; notes.push(n); last = n; }
        const lo = notes[0], hi = notes[notes.length - 1];
        if (lo < 24 || hi > 108) continue;
        const mid = Math.floor((lo + hi) / 2);
        let cost = Math.abs(mid - center) * 2;
        if (previous.length) {
          cost = 0;
          for (const n of notes) cost += Math.min(...previous.map(p => Math.abs(p - n)));
          cost += Math.floor(Math.abs(mid - center) / 2);
        }
        if (cost < bestCost) { bestCost = cost; best = notes; }
      }
    }
    if (withBass && best.length) {
      let b = Math.floor(best[0] / 12) * 12 + (c.bass ?? c.root);
      while (b >= best[0] - 4) b -= 12;
      if (b >= 24) best.unshift(b);
    }
    return best;
  }

  function detect(notes) {
    if (!notes.length) return null;
    const lowest = Math.min(...notes);
    const set = new Set(notes.map(mod12));
    if (set.size < 2) return null;
    const bassPC = mod12(lowest);
    let best = null, bestScore = -Infinity;
    for (let root = 0; root < 12; root++) for (const q of QNAMES) {
      const tones = new Set(Q[q].iv.map(i => mod12(root + i)));
      let hit = 0, extra = 0, missing = 0;
      set.forEach(p => tones.has(p) ? hit++ : extra++);
      tones.forEach(t => { if (!set.has(t)) missing++; });
      if (extra) continue;
      let score = hit * 2 - missing * 1.6;
      if (!set.has(root)) score -= 2.5;
      if (root === bassPC) score += 1.2;
      score -= Q[q].iv.length * 0.05;
      if (q === "power" && set.size > 2) score -= 5;
      if (score > bestScore) { bestScore = score; best = chord(root, q, bassPC); }
    }
    return bestScore > 0 ? best : null;
  }

  const SCALES = {
    major:[0,2,4,5,7,9,11], naturalMinor:[0,2,3,5,7,8,10], harmonicMinor:[0,2,3,5,7,8,11], melodicMinor:[0,2,3,5,7,9,11],
    dorian:[0,2,3,5,7,9,10], phrygian:[0,1,3,5,7,8,10], lydian:[0,2,4,6,7,9,11], mixolydian:[0,2,4,5,7,9,10],
    locrian:[0,1,3,5,6,8,10], majorPentatonic:[0,2,4,7,9], minorPentatonic:[0,3,5,7,10], blues:[0,3,5,6,7,10],
    phrygianDominant:[0,1,4,5,7,8,10]
  };
  const SCALE_NAMES = { major:"Maggiore", naturalMinor:"Minore naturale", harmonicMinor:"Minore armonica",
    melodicMinor:"Minore melodica", dorian:"Dorica", phrygian:"Frigia", lydian:"Lidia", mixolydian:"Misolidia",
    locrian:"Locria", majorPentatonic:"Pentatonica maggiore", minorPentatonic:"Pentatonica minore", blues:"Blues",
    phrygianDominant:"Frigia dominante" };
  const prefersFlats = k => [5,10,3,8,1,6].includes(k.minor ? mod12(k.tonic + 3) : k.tonic);
  const scaleSet = (k, type) => new Set(SCALES[type].map(i => mod12(k.tonic + i)));

  const MAJP = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88];
  const MINP = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17];
  function corr(a, b) {
    const ma = a.reduce((x,y)=>x+y,0)/12, mb = b.reduce((x,y)=>x+y,0)/12;
    let n=0, da=0, db=0;
    for (let i=0;i<12;i++){ n+=(a[i]-ma)*(b[i]-mb); da+=(a[i]-ma)**2; db+=(b[i]-mb)**2; }
    const d = Math.sqrt(da*db); return d === 0 ? 0 : n/d;
  }
  function detectKey(h, minorBias = 0) {
    if (h.reduce((a,b)=>a+b,0) <= 0) return null;
    let best = null, bs = -Infinity;
    for (let t=0;t<12;t++) for (const minor of [false,true]) {
      const p = minor ? MINP : MAJP;
      let r = corr(h, [...Array(12)].map((_,i)=>p[mod12(i-t)]));
      if (minor) r += minorBias;
      if (r > bs) { bs = r; best = { tonic: t, minor }; }
    }
    return best;
  }

  const DEG = { I:0, II:2, III:4, IV:5, V:7, VI:9, VII:11 };
  const SUF = {
    "": [ "major","minor" ], "7": ["dominant7","minor7"], "maj7": ["major7","minorMajor7"], "9": ["dominant9","minor9"],
    "maj9": ["major9","major9"], "6": ["six","minor6"], "add9": ["add9","minorAdd9"], "sus2": ["sus2","sus2"],
    "sus4": ["sus4","sus4"], "7sus4": ["dominant7sus4","dominant7sus4"], "5": ["power","power"],
    "dim": ["diminished","diminished"], "o": ["diminished","diminished"], "°": ["diminished","diminished"],
    "o7": ["diminished7","diminished7"], "°7": ["diminished7","diminished7"], "dim7": ["diminished7","diminished7"],
    "ø7": ["halfDiminished7","halfDiminished7"], "ø": ["halfDiminished7","halfDiminished7"], "m7b5": ["halfDiminished7","halfDiminished7"],
    "+": ["augmented","augmented"], "aug": ["augmented","augmented"], "7#9": ["dominant7sharp9","dominant7sharp9"],
    "11": ["minor11","minor11"], "13": ["dominant13","dominant13"]
  };
  function parseRoman(text) {
    let s = text.trim(), acc = 0;
    while (s[0] === "b" || s[0] === "#") { acc += s[0] === "b" ? -1 : 1; s = s.slice(1); }
    const m = s.match(/^[IViv]+/); if (!m) return null;
    const num = m[0], suffix = s.slice(num.length);
    const base = DEG[num.toUpperCase()]; if (base === undefined) return null;
    const upper = num === num.toUpperCase();
    const q = SUF[suffix]; if (!q) return null;
    return { offset: mod12(base + acc), quality: upper ? q[0] : q[1], symbol: text };
  }
  const prog = (t, w = 1) => ({ chords: t.split(" ").map(parseRoman).filter(Boolean), weight: w, text: t });

  function romanLabel(c, k) {
    const off = mod12(c.root - k.tonic);
    const names = {0:"I",2:"II",4:"III",5:"IV",7:"V",9:"VI",11:"VII"};
    const flat = {1:"bII",3:"bIII",6:"bV",8:"bVI",10:"bVII"};
    let n = names[off] || flat[off] || "?";
    if (k.minor) { const mn = {3:"III",8:"VI",10:"VII",4:"#III",9:"#VI",11:"#VII"}; n = mn[off] || n; }
    const fam = Q[c.quality].fam;
    if (fam === "min" || fam === "dim") { const pre = n.match(/^[b#]*/)[0]; n = pre + n.slice(pre.length).toLowerCase(); }
    const special = { major:"", minor:"", diminished:"°", halfDiminished7:"ø7", diminished7:"°7", augmented:"+",
      minor7:"7", minor6:"6", minor9:"9", minorAdd9:"add9", minorMajor7:"maj7" };
    return n + (c.quality in special ? special[c.quality] : Q[c.quality].sym);
  }

  // Colours: northern-lights palette instead of per-genre colours.
  const G = (id,name,emoji,minor,tonic,bpm,maj,min,progs,sig,cr,br,bars,oct) =>
    ({ id,name,emoji,prefersMinor:minor,defaultTonic:tonic,bpm,majorScale:maj,minorScale:min,progressions:progs,
       signatureNotes:sig,chordRhythm:cr,bassRhythm:br,barsPerChord:bars,octave:oct });
  const GENRES = [
    G("pop","Pop","🎤",false,0,110,"major","naturalMinor",[prog("I V vi IV",3),prog("vi IV I V",2),prog("I vi IV V",1.5),prog("IV I V vi"),prog("I IV vi V"),prog("I iii IV V",.7)],[2,9],"x---o---x---o---","x.......x...x...",1,60),
    G("rock","Rock","🎸",false,9,120,"mixolydian","minorPentatonic",[prog("I bVII IV I",2.5),prog("I IV V IV",2),prog("I V IV",1.5),prog("vi IV I V"),prog("I bIII IV I"),prog("I5 bVII5 IV5",1.2)],[10,3],"x-o-x-o-x-o-x-o-","x-x-x-x-x-x-x-x-",1,57),
    G("hiphop","Hip-Hop","🎧",true,2,90,"major","naturalMinor",[prog("i bVI bIII bVII",2),prog("i iv bVI V",1.5),prog("i7 iv7",2),prog("i bVII bVI V"),prog("i7 bVImaj7 bIII bVII")],[3,10,8],"x-------.---o---","x.....x...x.....",1,60),
    G("trap","Trap","🔥",true,5,140,"major","harmonicMinor",[prog("i bVI iv V",2),prog("i bII",1.5),prog("i iv bVI V",1.5),prog("i bVI bVII i"),prog("i v bVI V")],[1,11,8],"x---------------","x.......x..x....",1,60),
    G("rnb","R&B","💜",false,3,85,"major","dorian",[prog("Imaj7 vi7 ii7 V7",2),prog("ii9 V13 Imaj9",2),prog("IVmaj7 iii7 vi7",1.5),prog("Imaj7 IVmaj7",1.5),prog("IVmaj7 V7sus4 iii7 vi9")],[2,9,11],"x-----o-----o---","x.....x.....x...",1,60),
    G("jazz","Jazz","🎷",false,10,120,"major","melodicMinor",[prog("ii7 V7 Imaj7",3),prog("Imaj7 vi7 ii7 V7",2),prog("iii7 VI7 ii7 V7",1.5),prog("ii7 bII7 Imaj7",1.2),prog("Imaj7 I7 IVmaj7 iv7"),prog("iiø7 V7#9 i7")],[2,9,11,6],"..x..x.....x..x.","x...f...x...f...",1,60),
    G("blues","Blues","🎺",false,9,95,"blues","blues",[prog("I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7",3),prog("I7 IV7 I7 V7",1.5),prog("I7 IV7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 I7")],[3,6,10],"x--ox--ox--ox--o","x..fx..fx..fx..f",1,57),
    G("edm","EDM","⚡️",true,9,128,"major","naturalMinor",[prog("i bVI bIII bVII",3),prog("i bVII bVI bVII",1.5),prog("bVI bVII i",1.5),prog("i bIII bVII bVI")],[2,7],"x-------x-------","..x...x...x...x.",1,60),
    G("house","House","🏠",true,7,124,"major","dorian",[prog("i9 iv9",2.5),prog("i7 bVIImaj7 bVImaj7 bVII",1.5),prog("ii7 V7 Imaj7"),prog("i7 IV7",1.5)],[9,2],"..x...x...x...x.","..x...x...x...x.",1,60),
    G("techno","Techno","🔊",true,9,130,"mixolydian","phrygian",[prog("i bII",2),prog("i bVII",2),prog("i iv",1.5),prog("i5 bVI5",1.2)],[1,7],"x..x..x...x..x..","..xx..xx..xx..xx",2,57),
    G("melodictechno","Melodic Techno","🌌",true,2,124,"lydian","naturalMinor",[prog("i bVI bIII bVII",3),prog("i bVII bVI bVII",2),prog("iadd9 bVImaj7 bIIImaj7 bVII",2),prog("i v bVI iv",1.5)],[2,7],"aaaaaaaaaaaaaaaa","..x...x...x...x.",2,60),
    G("afrohouse","Melodic Afro House","🥁",true,9,122,"major","dorian",[prog("i bVII bVI bVII",2.5),prog("i iv bVII bIII",2),prog("i7 iv7 bVIImaj7",1.5),prog("i bVI bVII",1.5)],[9,2],"..x..x..x..x.x..","x..x...x..x.....",1,60),
    G("reggaeton","Reggaeton","🌴",true,4,95,"major","naturalMinor",[prog("i bVI bIII bVII",2.5),prog("i bVII bVI V",1.5),prog("i iv bVII bIII"),prog("i bVI bVII")],[3,7],"x..x..x.x..x..x.","x..x..x.x..x..x.",1,60),
    G("latin","Latin / Bossa","💃",false,5,130,"major","dorian",[prog("Imaj7 II7 ii7 V7",2),prog("ii7 V7 Imaj7 VI7",2),prog("Imaj7 bIIIo7 ii7 V7"),prog("i7 iv7 V7 i7")],[2,9,11],"x..x..x...x..x..","x..fx..fx..fx..f",1,60),
    G("country","Country","🤠",false,7,110,"majorPentatonic","naturalMinor",[prog("I IV V I",3),prog("I V vi IV",1.5),prog("I IV I V",1.5),prog("I I7 IV iv")],[2,9,3],"x.o.x.o.x.o.x.o.","x...f...x...f...",1,60),
    G("funk","Funk","🕺",true,4,105,"mixolydian","dorian",[prog("i9 IV9",3),prog("i7 iv7 i7 V7#9",1.5),prog("I7#9 IV9"),prog("i7 bVII7 i7 IV7")],[9,10,3],"x..x..x.x.x..x..","x..x.x..x.xx..x.",1,60),
    G("gospel","Gospel / Soul","🙌",false,8,80,"major","dorian",[prog("Imaj7 iii7 vi7 ii7 V7",2),prog("IV V iii vi ii V I",2),prog("IVmaj7 #ivø7 I V7"),prog("I I7 IV iv",1.5),prog("ii7 V7sus4 V7 Imaj9")],[2,9,10],"x-----x---x-----","x.....x...x.....",1,60),
    G("metal","Metal","🤘",true,4,140,"mixolydian","phrygian",[prog("i5 bVI5 bVII5 i5",2.5),prog("i5 bII5 i5 bVII5",2),prog("i bVI bIII bVII"),prog("i5 iv5 bVI5 V5")],[1,6],"x.x.x.x.x.x.x.x.","x.x.x.x.x.x.x.x.",1,52),
    G("reggae","Reggae","🇯🇲",false,7,75,"major","dorian",[prog("I IV",3),prog("I V vi IV",1.5),prog("I IV V IV",1.5),prog("ii V")],[2,9],"..x...x...x...x.","x.....x.x.......",1,60),
    G("classical","Classica","🎻",false,0,100,"major","harmonicMinor",[prog("I IV V I",2.5),prog("I vi ii V I",2),prog("I IV viio iii vi ii V I",1.5),prog("I V vi iii IV I IV V",1.5),prog("i iv V i")],[11,2],"aaaaaaaaaaaaaaaa","x-------x-------",1,60),
    G("lofi","Lo-Fi","☕️",false,5,80,"major","dorian",[prog("ii9 V9 Imaj9",2.5),prog("IVmaj7 iii7 ii7 Imaj7",2),prog("Imaj7 vi9 ii9 V7sus4",1.5),prog("IVmaj7 iii7 vi7 V7")],[2,9,11],"x-------..x-----","x.......x.......",1,60),
    G("afrobeats","Afrobeats","🌍",false,1,105,"major","dorian",[prog("vi IV I V",2),prog("ii V I",1.5),prog("I vi ii V",1.5),prog("IV V vi",1.5),prog("ii7 iii7 IVmaj7")],[2,9],"x..x..x...x..x..","x..x...xx.......",1,60),
    G("cinematic","Cinematic","🎬",true,2,80,"lydian","naturalMinor",[prog("i bVI bIII bVII",2),prog("i bVI iv V",2),prog("bVI bVII i",1.5),prog("i bIII bVII IV"),prog("I II IV I",.8)],[2,7],"x---------------","x---------------",2,60)
  ];

  const PIANOS = [
    { id:"grand", name:"Gran Coda da Concerto", emoji:"🎹", partials:[1,.55,.35,.22,.12,.08], B:.0004, decay:7, brightDecay:.3, release:.28, attack:.002, detune:1.5, fmRatio:0, fmIndex:0, fmDecay:.1, click:.05, velBright:.8, gain:1 },
    { id:"bright", name:"Pianoforte Brillante (Pop)", emoji:"✨", partials:[1,.72,.52,.38,.25,.16], B:.0005, decay:5, brightDecay:.4, release:.22, attack:.0015, detune:2, fmRatio:0, fmIndex:0, fmDecay:.1, click:.09, velBright:.6, gain:.85 },
    { id:"upright", name:"Pianoforte Verticale", emoji:"🪵", partials:[1,.6,.32,.26,.1,.05], B:.0007, decay:4, brightDecay:.25, release:.2, attack:.002, detune:4, fmRatio:0, fmIndex:0, fmDecay:.1, click:.07, velBright:.7, gain:1 },
    { id:"tine", name:"Piano Elettrico a Lamelle", emoji:"🔔", partials:[1,.12,.05,0,0,0], B:0, decay:3.8, brightDecay:.2, release:.3, attack:.002, detune:0, fmRatio:1, fmIndex:2.4, fmDecay:.35, click:.02, velBright:1, gain:1 },
    { id:"reed", name:"Piano Elettrico ad Ance", emoji:"🎛️", partials:[1,.5,.42,.16,.1,.04], B:0, decay:2.6, brightDecay:.3, release:.15, attack:.002, detune:0, fmRatio:1, fmIndex:1.1, fmDecay:.25, click:.03, velBright:1, gain:.9 },
    { id:"fm", name:"Piano Elettrico FM", emoji:"💎", partials:[1,.2,0,0,0,0], B:0, decay:3.2, brightDecay:.15, release:.35, attack:.001, detune:3, fmRatio:14, fmIndex:1.6, fmDecay:.08, click:0, velBright:1, gain:1 },
    { id:"honky", name:"Honky-Tonk", emoji:"🤠", partials:[1,.6,.4,.28,.15,.1], B:.0005, decay:4.2, brightDecay:.35, release:.2, attack:.002, detune:16, fmRatio:0, fmIndex:0, fmDecay:.1, click:.08, velBright:.5, gain:.85 },
    { id:"harpsichord", name:"Clavicembalo", emoji:"🎼", partials:[1,.9,.8,.7,.6,.5], B:.0002, decay:2.8, brightDecay:.6, release:.07, attack:.001, detune:2, fmRatio:0, fmIndex:0, fmDecay:.1, click:.22, velBright:.1, gain:.6 },
    { id:"toy", name:"Toy Piano", emoji:"🧸", partials:[1,0,.6,0,.4,0], B:.02, decay:1.3, brightDecay:.5, release:.1, attack:.001, detune:0, fmRatio:0, fmIndex:0, fmDecay:.1, click:.1, velBright:.4, gain:.8 },
    { id:"felt", name:"Felt Piano (Lo-Fi)", emoji:"🌙", partials:[1,.25,.08,.03,0,0], B:.0003, decay:3.5, brightDecay:.3, release:.5, attack:.009, detune:3, fmRatio:0, fmIndex:0, fmDecay:.1, click:.015, velBright:.5, gain:1.15 }
  ];

  const progressionKey = (g, k) => g.prefersMinor === k.minor ? k :
    (g.prefersMinor ? { tonic: mod12(k.tonic + 9), minor: true } : { tonic: mod12(k.tonic + 3), minor: false });
  const scaleFor = (g, k) => k.minor ? g.minorScale : g.majorScale;

  const SIMPLE = { maj:"major", dom:"major", min:"minor", dim:"diminished" };
  const RICH = { major:"major7", minor:"minor7", diminished:"halfDiminished7", dominant7:"dominant9", major7:"major9", minor7:"minor9", sus4:"dominant7sus4" };
  function adjust(c, complexity) {
    if (complexity === 1) return c;
    if (complexity === 0) {
      const f = Q[c.quality].fam;
      if (c.quality === "augmented") return c;
      return SIMPLE[f] ? chord(c.root, SIMPLE[f]) : c;
    }
    return RICH[c.quality] ? chord(c.root, RICH[c.quality]) : c;
  }
  const romanChord = (rc, k) => chord(k.tonic + rc.offset, rc.quality);

  function diatonic(k, type, complexity) {
    let ivs = SCALES[type];
    if (ivs.length !== 7) ivs = SCALES[k.minor ? "naturalMinor" : "major"];
    const out = [];
    for (let d = 0; d < 7; d++) {
      const r = ivs[d], third = mod12(ivs[(d+2)%7]-r), fifth = mod12(ivs[(d+4)%7]-r), sev = mod12(ivs[(d+6)%7]-r);
      let q = third===4&&fifth===7 ? "major" : third===3&&fifth===7 ? "minor" : third===3&&fifth===6 ? "diminished" : third===4&&fifth===8 ? "augmented" : null;
      if (!q) continue;
      if (complexity === 2) {
        const m = { "major11":"major7", "major10":"dominant7", "minor10":"minor7", "minor11":"minorMajor7", "diminished10":"halfDiminished7", "diminished9":"diminished7" };
        q = m[q + sev] || q;
      }
      out.push(chord(k.tonic + r, q));
    }
    return out;
  }

  class Engine {
    constructor(genre = GENRES[0]) {
      this.genre = genre; this.complexity = 1; this.fixedKey = null;
      this.maxSuggestions = 6; this.lowNote = 36; this.highNote = 96;
      this.history = []; this.hist = Array(12).fill(0); this.lastVoicing = [];
    }
    get currentKey() {
      if (this.fixedKey) return this.fixedKey;
      if (this.hist.reduce((a,b)=>a+b,0) <= 2) return { tonic: this.genre.defaultTonic, minor: this.genre.prefersMinor };
      return detectKey(this.hist, this.genre.prefersMinor ? .04 : -.02) || { tonic: this.genre.defaultTonic, minor: this.genre.prefersMinor };
    }
    reset() { this.history = []; this.hist = Array(12).fill(0); this.lastVoicing = []; }
    noteOn(n, v = 100) { for (let i=0;i<12;i++) this.hist[i] *= .985; this.hist[mod12(n)] += .5 + v/254; }
    commit(c) {
      const last = this.history[this.history.length-1];
      if (last && loose(last, c)) return;
      this.history.push(c); if (this.history.length > 8) this.history.shift();
      pcs(c).forEach(p => this.hist[p] += .6);
    }
    didPlay(v, c) { this.lastVoicing = v; this.commit(c); }

    suggest(held) {
      const g = this.genre, k = this.currentKey, pk = progressionKey(g, k), st = scaleFor(g, k), scale = scaleSet(k, st);
      const hs = [...held].sort((a,b)=>a-b);
      const current = detect(hs);
      const ctx = current || this.history[this.history.length-1] || null;
      const pool = new Map();
      for (const p of g.progressions) for (const rc of p.chords) {
        const c = adjust(romanChord(rc, pk), this.complexity), id = key(c);
        const ex = pool.get(id);
        pool.set(id, { c, roman: rc.symbol, base: Math.max(ex ? ex.base : 0, .4 * p.weight) });
      }
      for (const c of diatonic(k, st, this.complexity)) if (!pool.has(key(c))) pool.set(key(c), { c, roman: romanLabel(c,k), base: .15 });
      let prior = null;
      if (ctx) {
        const last = this.history[this.history.length-1];
        prior = last && loose(last, ctx) ? (this.history.length >= 2 ? this.history[this.history.length-2] : null) : (last || null);
      }
      const melody = hs.length === 1 ? mod12(hs[0]) : null;
      const scored = [];
      for (const { c, roman, base } of pool.values()) {
        let score = base, reason = "Tipico del " + g.name;
        if (ctx) {
          if (loose(c, ctx)) score -= 3;
          for (const p of g.progressions) {
            const cs = p.chords.map(rc => adjust(romanChord(rc, pk), this.complexity));
            if (cs.length < 2) continue;
            cs.forEach((x, i) => {
              if (!loose(x, ctx)) return;
              if (loose(cs[(i+1)%cs.length], c)) {
                score += 3 * p.weight;
                reason = "Progressione " + g.name + ": " + p.chords.map(r=>r.symbol).join("–");
                if (prior && loose(cs[(i-1+cs.length)%cs.length], prior)) score += 1.5 * p.weight;
              }
            });
          }
          const motion = mod12(c.root - ctx.root);
          score += motion===5 ? .9 : motion===7 ? .5 : (motion===2||motion===10) ? .35 : [3,4,8,9].includes(motion) ? .25 : 0;
          const cp = pcs(c), xp = pcs(ctx); let common = 0; cp.forEach(p => { if (xp.has(p)) common++; });
          score += .18 * common;
        } else if (mod12(c.root - pk.tonic) === 0) { score += 1; reason = "Accordo di tonica"; }
        if (melody !== null) {
          if (pcs(c).has(melody)) { score += 2.2; if (c.root === melody) score += .4; reason = "Armonizza la nota " + (prefersFlats(k)?FLATS:SHARPS)[melody]; }
          else score -= 1.5;
        }
        let outside = 0; pcs(c).forEach(p => { if (!scale.has(p)) outside++; });
        score -= .12 * outside;
        scored.push({ c, score, reason });
      }
      scored.sort((a,b) => a.score === b.score ? (chordName(a.c) < chordName(b.c) ? -1 : 1) : b.score - a.score);
      const center = hs.length ? Math.max(48, Math.min(72, Math.floor(hs.reduce((a,b)=>a+b,0)/hs.length))) : g.octave;
      let previous = hs.length > 1 ? hs : this.lastVoicing;
      const chords = scored.slice(0, this.maxSuggestions).map((s, rank) => {
        const v = voicing(s.c, center, previous, false);
        if (rank === 0) previous = v;
        return { chord: s.c, roman: romanLabel(s.c, k), score: s.score, rank, voicing: v, reason: s.reason };
      });
      // highlights: role 0 scale,1 signature,2 melody,3 alternative,4 primary
      const hl = new Map();
      const mark = (n, role, rank) => { if (n < this.lowNote || n > this.highNote) return; const e = hl.get(n); if (e && e.role >= role) return; hl.set(n, { role, rank }); };
      for (let n = this.lowNote; n <= this.highNote; n++) {
        const pc = mod12(n);
        if (scale.has(pc)) mark(n, 0, 99);
        if (scale.has(pc) && g.signatureNotes.some(o => mod12(k.tonic + o) === pc)) mark(n, 1, 99);
      }
      const mel = this.melodyHints(hs, k, scale, chords[0] && chords[0].chord);
      mel.forEach(n => mark(n, 2, 50));
      chords.slice(1, 3).forEach(s => s.voicing.forEach(n => mark(n, 3, s.rank)));
      if (chords[0]) {
        chords[0].voicing.forEach(n => mark(n, 4, 0));
        const low = chords[0].voicing[0];
        let b = Math.floor(low/12)*12 + chords[0].chord.root; while (b >= low) b -= 12;
        mark(b, 4, 0);
      }
      return { current, key: k, scale: st, chords, highlights: hl, melody: mel };
    }
    /// Genius mode: turns any key into the closest note that fits the song and picks the next chord
    /// that harmonises it while continuing the progression. Returns { note, chord, shift }.
    genius(note) {
      const k = this.currentKey, scale = scaleSet(k, scaleFor(this.genre, k));
      const ctx = this.suggest([]);
      const best = ctx.chords[0] ? pcs(ctx.chords[0].chord) : new Set();
      let m = note;
      for (const d of [0, -1, 1, -2, 2]) {
        const c = note + d;
        if (!scale.has(mod12(c))) continue;
        const twin = note - d;   // same distance on the other side
        if (d !== 0 && scale.has(mod12(twin)) && best.has(mod12(twin)) && !best.has(mod12(c))) { m = twin; break; }
        m = c; break;
      }
      const pc = mod12(m);
      let ch = (ctx.chords.find(s => pcs(s.chord).has(pc)) || {}).chord;
      if (!ch) { const r = this.suggest([m]); ch = r.chords[0] ? r.chords[0].chord : chord(k.tonic, k.minor ? "minor" : "major"); }
      return { note: m, chord: ch, shift: m - note };
    }
    /// Table for the 12 pitch classes (used by the real-time engines, recomputed as the song moves on).
    geniusTable() { return [...Array(12)].map((_, pc) => this.genius(60 + pc)); }

    melodyHints(held, k, scale, next) {
      if (!held.length) return [];
      const top = Math.max(...held), out = new Set();
      let up = top, fu = 0; while (fu < 2 && up < top + 7) { up++; if (scale.has(mod12(up))) { out.add(up); fu++; } }
      let dn = top, fd = 0; while (fd < 2 && dn > top - 7) { dn--; if (scale.has(mod12(dn))) { out.add(dn); fd++; } }
      if (next) pcs(next).forEach(pc => { let m = top - 5; while (mod12(m) !== pc) m++; if (m !== top) out.add(m); });
      for (const o of this.genre.signatureNotes) { const pc = mod12(k.tonic + o); for (let m = top-6; m <= top+6; m++) if (mod12(m) === pc && m !== top) out.add(m); }
      return [...out].filter(n => !held.includes(n)).sort((a,b)=>a-b);
    }
  }

  // ---------- Arpeggios (30) and melodies (20 per genre) ----------
  // Arpeggio steps: digit = index into the chord tones (+ the same tones an octave up),
  // c = whole chord, - = hold, . = rest. One bar of 16th notes.
  const ARPEGGIOS = [
    ["Su","0123012301230123"], ["Giù","3210321032103210"], ["Su e giù","0123432101234321"],
    ["Alberti","0212021202120212"], ["Alberti lento","0.2.1.2.0.2.1.2."], ["Spezzato","0213021302130213"],
    ["Ottave","0303030303030303"], ["Pedale","0102010201020102"], ["Cascata","5432105432104321"],
    ["Salita lunga","0123456701234567"], ["Terzine","012012012012012-"], ["Rullo gospel","0123c---0123c---"],
    ["Stab in levare","..c...c...c...c."], ["Trance gate","c.c.c.c.c.c.c.c."], ["Dembow","c..c..c.c..c..c."],
    ["Charleston","c..c......c....."], ["Bossa","0.2..1.20.2..1.2"], ["Ballata","0---2---1---2---"],
    ["Arpa","0123456776543210"], ["Piano pop","0-2-1-2-c---c-2-"], ["Ostinato","0202020202020202"],
    ["Pulsante","c-c-c-c-c-c-c-c-"], ["Sincopato","c..c..c...c.c..."], ["Eco","0.0.2.2.1.1.3.3."],
    ["Scala di accordi","0-1-2-3-4-5-6-7-"], ["Minimal","0-------2-------"], ["Reggae skank","..c-..c-..c-..c-"],
    ["Funk stab","c.cc..c.c..c.c.."], ["Rotolante","0213243546352413"], ["Cinematico","0---1---2---3---"]
  ];
  const MELODY_NAMES = ["Alba","Onda","Eco","Scintilla","Volo","Notte","Cometa","Respiro","Spirale","Orizzonte",
    "Ritornello","Danza","Riflesso","Sussurro","Vertigine","Marea","Lanterna","Brezza","Aurora","Galassia",
    "Fuoco","Neon","Miraggio","Tempesta","Cristallo","Satellite","Velluto","Fenice","Polvere di stelle","Eclissi"];
  const MELODY_COUNT = 30;
  const RHYTHMS = [
    // 0-5 sparse
    "x-------x-------","x-----x-------..","x---x-------x---","x-------x---x---","x--x----x-------","x-----------x-x-",
    // 6-13 medium
    "x---x---x-x-x---","x-x---x-x---x---","x--x--x-x---x---","x---x-x---x-x---","x-x-x---x-------","..x-x-x-x---x---",
    "x--x--x---x-x---","x---x--x--x-x---",
    // 14-19 dense
    "x-x-x-x-x-x-x-x-","x-x-x-x-xxx-x---","x-xxx-x-x-xxx-x-","x.x.x.x.xx.xx.x.","xx-xx-x-xx-xx-x-","x-x-xx-xx-x-xx-x"
  ];
  // Hook rhythms heard in each genre's hits (16th grid). They are tried first.
  const GENRE_RHYTHMS = {
    pop: ["x-x-x---x-x-x---","..x-x-x-x--x-x--","x--x--x-x-------","x-xx-x---x-x-x--"],
    rock: ["x---x---x-x-x---","x-x-x-x-x---x---","x--x--x-x-x-----"],
    hiphop: ["x--x--x---x-----","..x-x--x--x-x---","x-x--x--x-x-----"],
    trap: ["x--x--x--x--x-x-","x-----x-x--x----","x--x--x---------"],
    rnb: ["x-----x-x-x-----","..x---x-x--x----","x--x----x-x-x---"],
    jazz: ["x--x-x--x--x-x--","..x-x-x-x-x--x--","x-x--x-x--x-x-x-"],
    blues: ["x--x--x---x-----","..x--x-x--------","x-x--x--x-------"],
    edm: ["x-x-x-x-x--x-x--","x--x--x-x--x--x-","xx-x-x-xx-x-x---"],
    house: ["..x...x...x.x.x.","x--x--x---x-x---","..x-x-x-..x-x-x-"],
    techno: ["x-x-x-x-x-x-x-x-","x--x--x-x--x--x-","x---x---x---x---"],
    melodictechno: ["x-x-x-x-x---x---","x--x--x-x-------","x---x-x-x---x-x-"],
    afrohouse: ["x..x..x...x.x...","..x..x..x.x.....","x..x.x..x..x...."],
    reggaeton: ["x..x..x.x..x..x.","..x..x.x..x..x..","x..x..x.x-x-x---"],
    latin: ["x..x..x...x.x...","x.x..x.x..x.x...","..x.x..x.x..x..."],
    country: ["x-x-x---x-x-x---","x---x-x-x-------","..x-x-x-x---x---"],
    funk: ["x.xx.x..x.x.xx..","..x.xx.x..x.x.x.","x..x.x..xx.x...."],
    gospel: ["x-----x-x-x-----","x--x--x-x-----x-","..x-x-x-x-------"],
    metal: ["xxx-xxx-xxx-xx-x","x-x-x-x-xx-xx-x-","x-xxx-xxx-x-x---"],
    reggae: ["....x-x.....x-x.","x---..x-x---..x-","..x-x---..x-x---"],
    classical: ["x-x-x-x-x---x---","x---x-x-x-x-x---","x-xxx-x-x-------"],
    lofi: ["x-----x---x-----","..x---x-x-------","x---x-------x-x-"],
    afrobeats: ["x..x..x.x.x..x..","..x..x..x.x.x...","x..x.x..x..x.x.."],
    cinematic: ["x-------x---x---","x-----------x---","x---x---x-------"]
  };
  // Hook devices per genre: rep = repeated-note hook, oct = octave leap in the chorus,
  // chrom = chromatic approach notes, blue = blue notes, lift = chorus register lift (degrees).
  const DEVICES = {
    pop:{rep:1,oct:1,lift:2}, rock:{blue:1,lift:2}, hiphop:{rep:1,blue:1,lift:1}, trap:{rep:1,lift:1},
    rnb:{chrom:1,lift:2}, jazz:{chrom:1,lift:2}, blues:{blue:1,lift:1}, edm:{rep:1,oct:1,lift:3},
    house:{rep:1,lift:2}, techno:{rep:1,lift:1}, melodictechno:{rep:1,oct:1,lift:3}, afrohouse:{rep:1,chrom:1,lift:2}, reggaeton:{rep:1,lift:2}, latin:{chrom:1,lift:2}, country:{lift:2},
    funk:{chrom:1,blue:1,rep:1,lift:1}, gospel:{chrom:1,blue:1,lift:3}, metal:{oct:1,lift:2}, reggae:{rep:1,lift:1},
    classical:{chrom:1,lift:2}, lofi:{chrom:1,lift:1}, afrobeats:{rep:1,lift:2}, cinematic:{oct:1,lift:3}
  };
  const DENSITY = { pop:1, rock:1, hiphop:1, trap:0, rnb:0, jazz:2, blues:1, edm:2, house:2, techno:2, melodictechno:1, afrohouse:1, reggaeton:1, latin:2,
    country:1, funk:2, gospel:0, metal:2, reggae:1, classical:2, lofi:0, afrobeats:2, cinematic:0 };
  const CONTOURS = [[0,1,2,3,4,3,2,1],[0,0,1,2,2,3,4,5],[5,4,4,3,2,1,1,0],[0,2,1,3,2,4,3,1],
                    [0,3,1,4,2,5,1,0],[2,2,3,2,2,1,2,2],[0,2,4,2,1,3,5,3],[0,4,1,5,2,4,0,3],
                    [4,4,4,2,3,3,3,1],[0,0,4,4,3,2,1,0]];

  // Deterministic random numbers (identical in the Swift and C++ engines).
  function rng(seed) {
    let a = seed >>> 0;
    return n => {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return (((t ^ (t >>> 14)) >>> 0) % n);
    };
  }
  // Every genre × arpeggio × melody × song seed gives its own tune.
  const songSeed = (gi, arp, melody, seed) =>
    ((gi + 1) * 7919 + (arp + 2) * 31337 + (melody + 1) * 104729 + seed * 15485863) >>> 0;

  function rhythmPool(id) {
    const d = DENSITY[id] ?? 1;
    const sparse = [0,1,2,3,4,5], medium = [6,7,8,9,10,11,12,13], dense = [14,15,16,17,18,19];
    const generic = (d === 0 ? sparse.concat(medium.slice(0, 4)) : d === 1 ? medium.concat(sparse.slice(0, 3)) : dense.concat(medium.slice(3)))
      .map(i => RHYTHMS[i]);
    const own = GENRE_RHYTHMS[id] || [];
    return own.concat(own, generic);   // genre hook rhythms count double
  }

  /// A hook-based melody: a 2-bar motif repeated in an A A' B A form, with the chorus (B) lifted higher,
  /// strong beats landing on chord tones and the genre's own hook devices.
  function melodyEvents(g, gi, pk, chords, arp, melody, seed, spc) {
    const R = rng(songSeed(gi, arp, melody, seed));
    const dev = DEVICES[g.id] || {};
    const scale = new Set(SCALES[scaleFor(g, pk)].map(i => mod12(pk.tonic + i)));
    const center = g.octave + 10, lo = center - 9, hi = center + 14;
    const notes = []; for (let n = lo; n <= hi; n++) if (scale.has(mod12(n))) notes.push(n);
    let base = 0; for (let i = 0; i < notes.length; i++) if (Math.abs(notes[i] - (center - 3)) < Math.abs(notes[base] - (center - 3))) base = i;
    const pool = rhythmPool(g.id);
    const rA = pool[(melody * 3 + R(pool.length)) % pool.length];
    const rB = pool[(melody * 7 + 2 + R(pool.length)) % pool.length];
    const cA = CONTOURS[(melody + R(CONTOURS.length)) % CONTOURS.length];
    const cB = CONTOURS[(melody * 3 + 1 + R(CONTOURS.length)) % CONTOURS.length];
    const lift = (dev.lift || 2), register = R(3) - 1;
    const repHook = dev.rep && R(3) !== 0;          // first notes of the motif on one pitch
    const sig = g.signatureNotes.map(o => mod12(pk.tonic + o));
    const blue = [mod12(pk.tonic + 3), mod12(pk.tonic + 6), mod12(pk.tonic + 10)];
    const events = []; const total = spc * chords.length;
    let prev = -1;
    const nearestChordTone = (n, chordPcs) => {
      let best = n, bd = 99;
      for (const m of notes) if (chordPcs.has(mod12(m)) && Math.abs(m - n) < bd) { bd = Math.abs(m - n); best = m; }
      return best;
    };
    for (let b = 0; b < total / 16; b++) {
      const ci = Math.floor(b * 16 / spc), chordPcs = pcs(chords[ci]);
      const phrase = Math.floor(b / 2) % 4, inPhrase = b % 2;
      const isB = phrase === 2, rhythm = isB ? rB : rA, contour = isB ? cB : cA;
      const shift = register + (isB ? lift : 0) + (phrase === 1 && inPhrase === 1 ? -1 : 0);
      const starts = []; for (let s = 0; s < 16; s++) if (rhythm[s] === "x") starts.push(s);
      starts.forEach((s, k) => {
        let e = s + 1; while (e < 16 && rhythm[e] === "-") e++;
        const pos = inPhrase * 4 + Math.floor(s / 4);
        let idx = Math.max(0, Math.min(notes.length - 1, base + contour[pos] + shift));
        if (repHook && inPhrase === 0 && k > 0 && k < 3) idx = Math.max(0, Math.min(notes.length - 1, base + contour[0] + shift));
        let n = notes[idx];
        if (s % 8 === 0 || k === 0) n = nearestChordTone(n, chordPcs);
        else if (dev.blue && R(5) === 0) {
          const bn = [n - 1, n + 1, n - 2].find(m => blue.includes(mod12(m)) && m >= lo && m <= hi);
          if (bn !== undefined) n = bn;
        } else if (R(6) === 0) {
          const near = notes.filter(m => sig.includes(mod12(m)) && Math.abs(m - n) <= 3);
          if (near.length) n = near[R(near.length)];
        }
        // Chorus opening jumps an octave for a big lift.
        if (dev.oct && isB && inPhrase === 0 && k === 0 && n + 12 <= hi + 5) n += 12;
        if (n === prev && !(repHook && inPhrase === 0) && R(2) === 0) {
          const j = notes.indexOf(n) + (R(2) ? 1 : -1); if (j >= 0 && j < notes.length) n = notes[j];
        }
        // Chromatic approach: a short note a semitone below the next strong-beat target.
        const next = starts[k + 1];
        if (dev.chrom && next !== undefined && next % 8 === 0 && e - s >= 2 && R(3) === 0) {
          const target = nearestChordTone(notes[Math.max(0, Math.min(notes.length - 1, base + contour[inPhrase * 4 + Math.floor(next / 4)] + shift))], chordPcs);
          const mid = s + Math.max(1, Math.floor((e - s) / 2));
          events.push({ step: b * 16 + s, note: n, vel: 92, lane: 1 }, { step: b * 16 + mid, note: n, vel: 0, lane: 1 });
          const ap = target - 1;
          events.push({ step: b * 16 + mid, note: ap, vel: 78, lane: 1 }, { step: b * 16 + e >= total ? 0 : b * 16 + e, note: ap, vel: 0, lane: 1 });
          prev = ap; return;
        }
        const start = b * 16 + s, stop = b * 16 + e;
        const vel = (s % 4 === 0 ? 100 : 82) + R(9) - 4;
        events.push({ step: start, note: n, vel, lane: 1 });
        events.push({ step: stop >= total ? 0 : stop, note: n, vel: 0, lane: 1 });
        prev = n;
      });
    }
    return events;
  }

  /// Builds the genre-player loop. arp: -1 = genre rhythm, 0..29 = arpeggio. melody: -1 = none, 0..19.
  function buildPattern(g, k, progIndex = 0, complexity = 1, arp = -1, melody = -1, seed = 0) {
    const pk = progressionKey(g, k);
    const p = g.progressions[Math.max(0, Math.min(progIndex, g.progressions.length - 1))];
    const chords = p.chords.map(rc => adjust(romanChord(rc, pk), complexity));
    const spc = 16 * Math.max(1, g.barsPerChord), total = spc * chords.length, events = [];
    const arpSteps = arp >= 0 && arp < ARPEGGIOS.length ? ARPEGGIOS[arp][1] : null;
    let prev = [];
    chords.forEach((c, ci) => {
      const v = voicing(c, g.octave, prev, false); prev = v;
      const ext = v.concat(v.map(n => n + 12)).slice(0, 8);
      const arpOrder = v.length <= 1 ? [0] : v.length === 2 ? [0,1] : v.length === 3 ? [0,2,1,2] : [0,2,1,3];
      let bass = Math.floor(v[0]/12)*12 + c.root; while (bass + 12 >= v[0]) bass -= 12; if (bass < 24) bass += 12;
      const iv = Q[c.quality].iv, fifth = iv.includes(7) ? 7 : iv.includes(6) ? 6 : iv.includes(8) ? 8 : 7;
      let on = [], bOn = null, ai = 0;
      const offAll = step => { on.forEach(n => events.push({ step, note: n, vel: 0, lane: 0 })); on = []; };
      for (let s = 0; s < spc; s++) {
        const step = ci * spc + s, bh = g.bassRhythm[s % 16];
        if (arpSteps) {
          const ch = arpSteps[s % 16];
          if (ch === "c") { offAll(step); on = v.slice(); v.forEach(n => events.push({ step, note: n, vel: s % 4 === 0 ? 100 : 80, lane: 0 })); }
          else if (ch >= "0" && ch <= "9") { offAll(step); const n = ext[(+ch) % ext.length]; on = [n]; events.push({ step, note: n, vel: s % 4 === 0 ? 96 : 74, lane: 0 }); }
          else if (ch === ".") offAll(step);
        } else {
          const ch = g.chordRhythm[s % 16];
          if (ch === "x" || ch === "o") { offAll(step); on = v.slice(); v.forEach(n => events.push({ step, note: n, vel: ch === "x" ? 104 : 78, lane: 0 })); }
          else if (ch === "a") { offAll(step); const n = v[arpOrder[ai % arpOrder.length]]; ai++; on = [n]; events.push({ step, note: n, vel: ai % 4 === 1 ? 92 : 72, lane: 0 }); }
          else if (ch === ".") offAll(step);
        }
        if (bh === "x" || bh === "f" || bh === "o") { if (bOn !== null) events.push({ step, note: bOn, vel: 0, lane: 0 }); const n = bh === "x" ? bass : bh === "f" ? bass + fifth : bass + 12; bOn = n; events.push({ step, note: n, vel: bh === "x" ? 100 : 84, lane: 0 }); }
        else if (bh === ".") { if (bOn !== null) events.push({ step, note: bOn, vel: 0, lane: 0 }); bOn = null; }
      }
      const end = (ci + 1) * spc, es = end === total ? 0 : end;
      offAll(es);
      if (bOn !== null) events.push({ step: es, note: bOn, vel: 0, lane: 0 });
    });
    if (melody >= 0) events.push(...melodyEvents(g, GENRES.indexOf(g), pk, chords, arp, melody % MELODY_COUNT, seed, spc));
    events.sort((a, b) => a.step === b.step ? ((a.vel === 0) === (b.vel === 0) ? 0 : a.vel === 0 ? -1 : 1) : a.step - b.step);
    return { events, total, chords, spc };
  }

  /// Chord voiced just below the melody note, with the root in the bass.
  function geniusVoicing(c, melody) {
    const out = [];
    const tones = [...new Set(Q[c.quality].iv.map(i => mod12(c.root + i)))];
    for (const pc of tones) {
      let n = melody - 2; while (mod12(n) !== pc) n--;
      if (n >= melody - 14 && n >= 28) out.push(n);
    }
    let b = melody - 17; while (mod12(b) !== c.root) b--;
    if (b >= 24) out.push(b);
    return [...new Set(out)].sort((x, y) => x - y);
  }

  return { geniusVoicing, mod12, SHARPS, FLATS, ITALIAN, Q, chord, chordName, detect, voicing, detectKey, parseRoman, romanLabel,
           GENRES, PIANOS, SCALE_NAMES, Engine, buildPattern, prefersFlats, pcs, ARPEGGIOS, MELODY_NAMES, MELODY_COUNT, rng };
})();
if (typeof module !== "undefined") module.exports = CP;
