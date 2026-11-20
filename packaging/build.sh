#!/usr/bin/env bash
# Costruisce la cartella "vendita/" con gli installer per Mac, Windows, Linux e la versione web.
# Requisiti (Linux): python3 + Pillow, node/npx, xorriso, nsis (makensis).
#   sudo apt-get install -y xorriso nsis && pip install pillow
# Uso:  bash packaging/build.sh [versione]
set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packaging"
WORK="$PKG/.build"
OUT="$ROOT/vendita"
APP="Aurora Signal"

for tool in python3 npx xorriso makensis; do
  command -v "$tool" >/dev/null || { echo "Manca lo strumento: $tool" >&2; exit 1; }
done

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"/{Mac,Windows,Linux,Web}

echo "1/7  Compilo l'app per i browser più vecchi (ES2017)…"
TOOLS="$PKG/.tools"
if [ ! -x "$TOOLS/node_modules/.bin/esbuild" ]; then
  mkdir -p "$TOOLS" && echo '{"name":"aurora-build-tools","private":true}' > "$TOOLS/package.json"
  (cd "$TOOLS" && npm i -s esbuild@0.24.0 >/dev/null)
fi
python3 - "$ROOT/aurora/index.html" "$WORK/app.html" "$TOOLS/node_modules/.bin/esbuild" "$VERSION" <<'PY'
import re, subprocess, sys
src, dst, esbuild, version = sys.argv[1:]
html = open(src, encoding="utf-8").read()
m = re.search(r"<script>([\s\S]*)</script>", html)
js = subprocess.run([esbuild, "--loader=js", "--target=es2017,chrome58,firefox57,safari11,edge79"],
                    input=m.group(1), capture_output=True, text=True, check=True).stdout
html = html[:m.start(1)] + "\n" + js + html[m.end(1):]
html = html.replace("<title>Aurora Signal</title>", f'<title>Aurora Signal</title>\n<meta name="version" content="{version}">')
open(dst, "w", encoding="utf-8").write(html)
PY

echo "2/7  Creo le icone…"
python3 "$PKG/make_icons.py" "$WORK/icons" >/dev/null

echo "3/7  Preparo i documenti…"
python3 - "$PKG/docs" "$WORK/docs" "$VERSION" <<'PY'
import sys, pathlib
src, dst, v = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
dst.mkdir(parents=True, exist_ok=True)
for f in src.glob("*.txt"):
    t = f.read_text(encoding="utf-8").replace("@VERSION@", v)
    # CRLF + BOM: si leggono bene anche con il Blocco note di Windows 7
    (dst / f.name).write_bytes(b"\xef\xbb\xbf" + t.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
PY

echo "4/7  Costruisco l'app per Mac e il DMG…"
STAGE="$WORK/dmg"
BUNDLE="$STAGE/$APP.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
sed "s/@VERSION@/$VERSION/g" "$PKG/mac/Info.plist" > "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
install -m 755 "$PKG/mac/AuroraSignal" "$BUNDLE/Contents/MacOS/AuroraSignal"
cp "$WORK/app.html" "$BUNDLE/Contents/Resources/app.html"
cp "$WORK/icons/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
ln -s /Applications "$STAGE/Applicazioni"
cp "$WORK/docs/LEGGIMI.txt" "$STAGE/LEGGIMI - Come installare.txt"
cp "$WORK/icons/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
xorriso -as mkisofs -quiet -V "Aurora Signal" -volid-date c \
  -hfsplus -apm-block-size 2048 -hfs-bless-by p "/" \
  -R -J -joliet-long -o "$OUT/Mac/Aurora-Signal-$VERSION.dmg" "$STAGE" 2>/dev/null \
|| xorriso -as mkisofs -quiet -V "Aurora Signal" -hfsplus -apm-block-size 2048 -R -J -joliet-long \
  -o "$OUT/Mac/Aurora-Signal-$VERSION.dmg" "$STAGE"

echo "5/7  Costruisco l'installer per Windows…"
makensis -V2 -DVERSION="$VERSION" \
  -DOUTFILE="$OUT/Windows/Aurora-Signal-Setup-$VERSION.exe" \
  -DAPPHTML="$WORK/app.html" -DICON="$WORK/icons/icon.ico" \
  -DLICENSE="$WORK/docs/LICENZA.txt" -DREADME="$WORK/docs/LEGGIMI.txt" \
  "$PKG/windows/installer.nsi"

echo "6/7  Versione portatile Windows, Linux e Web…"
python3 - "$WORK" "$OUT" <<'PY'
import sys, zipfile, tarfile, io, pathlib, time
work, out = map(pathlib.Path, sys.argv[1:])
app = (work / "app.html").read_bytes()
docs = {n: (work / "docs" / n).read_bytes() for n in ("LEGGIMI.txt", "LICENZA.txt")}

# Windows portatile
cmd = b'@echo off\r\nstart "" "%~dp0aurora-signal.html"\r\n'
with zipfile.ZipFile(out / "Windows" / "Aurora-Signal-Windows-Portatile.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("Aurora Signal/aurora-signal.html", app)
    z.writestr("Aurora Signal/Avvia Aurora Signal.cmd", cmd)
    z.write(work / "icons" / "icon.ico", "Aurora Signal/icon.ico")
    for n, b in docs.items(): z.writestr(f"Aurora Signal/{n}", b)

# Linux
run = b'''#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
for B in google-chrome chromium chromium-browser microsoft-edge brave-browser; do
  command -v "$B" >/dev/null 2>&1 && exec "$B" --app="file://$DIR/aurora-signal.html"
done
exec xdg-open "$DIR/aurora-signal.html"
'''
inst = b'''#!/bin/sh
# Aggiunge Aurora Signal al menu delle applicazioni
set -e
DIR="$HOME/.local/share/aurora-signal"
mkdir -p "$DIR" "$HOME/.local/share/applications"
cp "$(dirname "$0")"/aurora-signal.html "$(dirname "$0")"/aurora-signal.sh "$(dirname "$0")"/icon.png "$DIR/"
chmod +x "$DIR/aurora-signal.sh"
cat > "$HOME/.local/share/applications/aurora-signal.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aurora Signal
Comment=Segnali compra/vendi per le criptovalute
Exec="$DIR/aurora-signal.sh"
Icon=$DIR/icon.png
Categories=Finance;Office;
Terminal=false
EOF
echo "Aurora Signal installato: lo trovi nel menu delle applicazioni."
'''
with tarfile.open(out / "Linux" / "aurora-signal-linux.tar.gz", "w:gz") as t:
    def add(name, data, mode=0o644):
        i = tarfile.TarInfo("aurora-signal/" + name); i.size = len(data); i.mode = mode; i.mtime = time.time()
        t.addfile(i, io.BytesIO(data))
    add("aurora-signal.html", app)
    add("aurora-signal.sh", run, 0o755)
    add("installa.sh", inst, 0o755)
    add("icon.png", (work / "icons" / "icon_256.png").read_bytes())
    for n, b in docs.items(): add(n, b.replace(b"\r\n", b"\n"))

(out / "Web" / "Aurora Signal.html").write_bytes(app)
for n, b in docs.items(): (out / n).write_bytes(b)
PY

echo "7/7  Calcolo le impronte SHA-256…"
(cd "$OUT" && find . -type f ! -name 'SHA256SUMS.txt' | sort | sed 's#^\./##' | while read -r f; do sha256sum "$f"; done > SHA256SUMS.txt)

echo
echo "Fatto. Cartella pronta: $OUT"
find "$OUT" -type f -printf '  %P  (%s byte)\n' | sort
