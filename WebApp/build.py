#!/usr/bin/env python3
"""Builds the single-file web app: inlines src/engine.js into src/template.html."""
import pathlib
root = pathlib.Path(__file__).parent
html = (root / "src/template.html").read_text().replace("/*ENGINE*/", (root / "src/engine.js").read_text())
(root / "ChordPilot.html").write_text(html)
print("ChordPilot.html", len(html), "bytes")
