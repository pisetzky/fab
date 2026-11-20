#!/usr/bin/env python3
"""Genera l'icona di Aurora Signal: PNG 1024, AppIcon.icns (Mac) e icon.ico (Windows)."""
import io, math, struct, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "build/icons")
OUT.mkdir(parents=True, exist_ok=True)
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_icon():
    # Sfondo: notte polare con sfumatura verticale
    bg = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(bg)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp((4, 9, 26), (12, 34, 66), y / S))

    # Bande dell'aurora, poi sfocate
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    bands = [
        ((61, 255, 168), 330, 120, 0.0, 70),
        ((0, 212, 255), 420, 100, 1.3, 60),
        ((155, 107, 255), 500, 90, 2.1, 55),
        ((255, 95, 210), 570, 70, 3.0, 40),
    ]
    for col, base, amp, ph, w in bands:
        pts = [(x, base + amp * math.sin(x / S * 2.4 * math.pi + ph) - 0.15 * x) for x in range(-50, S + 60, 8)]
        g.line(pts, fill=col, width=w, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(38))
    img = Image.blend(bg, Image.eval(glow, lambda v: v), 0.0)
    img = Image.composite(glow, bg, glow.convert("L").point(lambda v: min(255, int(v * 1.25))))

    # Stelle
    d = ImageDraw.Draw(img)
    for x, y, r in [(150, 140, 4), (820, 170, 3), (690, 90, 3), (300, 260, 2), (900, 330, 3), (90, 400, 2)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(235, 246, 255))

    # Linea del grafico in salita con bagliore
    chart = [(170, 780), (300, 700), (400, 740), (520, 600), (620, 650), (760, 470), (860, 400)]
    halo = Image.new("L", (S, S), 0)
    ImageDraw.Draw(halo).line(chart, fill=255, width=60, joint="curve")
    halo = halo.filter(ImageFilter.GaussianBlur(26))
    img = Image.composite(Image.new("RGB", (S, S), (61, 255, 168)), img, halo.point(lambda v: int(v * 0.55)))
    d = ImageDraw.Draw(img)
    d.line(chart, fill=(240, 255, 250), width=34, joint="curve")
    for x, y in chart:
        d.ellipse([x - 17, y - 17, x + 17, y + 17], fill=(240, 255, 250))
    # Punta della freccia
    d.polygon([(860, 330), (930, 420), (820, 445)], fill=(240, 255, 250))

    # Maschera arrotondata con margine (stile macOS moderno)
    pad, rad = 92, 185
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad, pad, S - pad, S - pad], rad, fill=255)
    inner = img.resize((S - 2 * pad, S - 2 * pad), Image.LANCZOS)
    canvas = Image.new("RGB", (S, S))
    canvas.paste(inner, (pad, pad))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(canvas, (0, 0), mask)
    # Ombra leggera
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sm = mask.filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.45))
    shadow.putalpha(sm)
    final = Image.alpha_composite(Image.new("RGBA", (S, S), (0, 0, 0, 0)), shadow.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -14)))
    return Image.alpha_composite(final, out)


def png_bytes(im, size):
    b = io.BytesIO()
    im.resize((size, size), Image.LANCZOS).save(b, "PNG")
    return b.getvalue()


def write_icns(im, path):
    # Voci PNG supportate da macOS 10.5+ (ic07-ic10) e 10.7+ (icp4-icp6)
    types = [(b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)]
    body = b"".join(t + struct.pack(">I", len(p) + 8) + p for t, p in ((t, png_bytes(im, s)) for t, s in types))
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


icon = make_icon()
icon.save(OUT / "icon_1024.png")
icon.resize((256, 256), Image.LANCZOS).save(OUT / "icon_256.png")
write_icns(icon, OUT / "AppIcon.icns")
icon.save(OUT / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icone create in", OUT)
