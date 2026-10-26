# Hauptmenü-Icon der Eieruhr: Sanduhr im Stil der Squeezebox-Icons (41x41)
import sys
from PIL import Image, ImageDraw
S = 8                       # Supersampling
base = Image.open(sys.argv[1]).convert("RGBA")
N = 41 * S
mask = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(mask)
def p(x, y): return (x * S, y * S)
# Rahmen oben/unten
d.rounded_rectangle([p(10.5, 6), p(30.5, 9.5)], radius=1.5 * S, fill=255)
d.rounded_rectangle([p(10.5, 31.5), p(30.5, 35)], radius=1.5 * S, fill=255)
# Glas als Umriss: obere und untere Glocke
w = int(1.8 * S)
top = [p(13, 9.5), p(28, 9.5), p(28, 12), p(22, 20), p(19, 20), p(13, 12)]
bot = [p(19, 21), p(22, 21), p(28, 29), p(28, 31.5), p(13, 31.5), p(13, 29)]
for poly in (top, bot):
    d.line(poly + [poly[0]], fill=255, width=w, joint="curve")
# Sand: Rest oben, Haufen unten, Rinnsal
d.polygon([p(16.5, 14.5), p(24.5, 14.5), p(21.2, 19), p(19.8, 19)], fill=255)
d.polygon([p(20.5, 24), p(27, 29.5), p(27, 31.5), p(14, 31.5), p(14, 29.5)], fill=255)
d.line([p(20.5, 19), p(20.5, 25)], fill=255, width=int(1.2 * S))
mask = mask.resize((41, 41), Image.LANCZOS)
# dunkles Glyph mit Verlauf wie bei den Originalen
grad = Image.new("RGBA", (41, 41))
for y in range(41):
    t = min(1, max(0, (y - 6) / 29))
    c = tuple(int(a + (b - a) * t) for a, b in zip((120, 120, 132), (50, 50, 56)))
    for x in range(41):
        grad.putpixel((x, y), c + (255,))
base.paste(grad, (0, 0), mask)
base.save(sys.argv[2])
base.resize((164, 164), Image.NEAREST).save(sys.argv[3])
