import sys, math
from PIL import Image, ImageDraw
S = 256
SUN = (255, 196, 46, 255); MOON = (236, 230, 200, 255)
CLOUD = (232, 236, 242, 255); CLOUD2 = (150, 160, 175, 255); DARK = (110, 118, 132, 255)
RAIN = (80, 165, 255, 255); SNOW = (255, 255, 255, 255); BOLT = (255, 214, 0, 255); FOG = (170, 178, 190, 255)

def sun(d, cx, cy, r, rays=True):
    if rays:
        for i in range(8):
            a = math.pi / 4 * i
            x1, y1 = cx + math.cos(a) * r * 1.35, cy + math.sin(a) * r * 1.35
            x2, y2 = cx + math.cos(a) * r * 1.8, cy + math.sin(a) * r * 1.8
            d.line((x1, y1, x2, y2), fill=SUN, width=max(6, int(r * .22)))
            for x, y in ((x1, y1), (x2, y2)):
                w = max(6, int(r * .22)) / 2
                d.ellipse((x - w, y - w, x + w, y + w), fill=SUN)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=SUN)

def moon(img, cx, cy, r):
    m = Image.new("L", (S, S), 0); md = ImageDraw.Draw(m)
    md.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    o = r * .55
    md.ellipse((cx - r + o, cy - r - o * .6, cx + r + o, cy + r - o * .6), fill=0)
    img.paste(Image.new("RGBA", (S, S), MOON), (0, 0), m)

def cloud(d, x, y, w, col):
    # x,y = linke untere Ecke, w = Breite
    h = w * .32
    d.rounded_rectangle((x, y - h, x + w, y), radius=h / 2, fill=col)
    d.ellipse((x + w * .12, y - h - w * .22, x + w * .52, y - h + w * .18), fill=col)
    d.ellipse((x + w * .36, y - h - w * .36, x + w * .86, y - h + w * .14), fill=col)

def outline_cloud(img, x, y, w, col):
    # Wolke mit dunklem Rand, damit sie sich vor Sonne/Mond abhebt
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sd = ImageDraw.Draw(sh)
    cloud(sd, x - 8, y + 8, w + 16, (0, 0, 0, 255))
    m = sh.split()[3]
    img.paste(Image.new("RGBA", (S, S), (0, 0, 0, 0)), (0, 0), m)  # Loch freistanzen
    cloud(ImageDraw.Draw(img), x, y, w, col)

def drops(d, n, y0, length, xs=None):
    xs = xs or [80 + i * 48 for i in range(n)]
    for x in xs[:n]:
        d.line((x, y0, x - length * .35, y0 + length), fill=RAIN, width=14)
        d.ellipse((x - 7, y0 - 7, x + 7, y0 + 7), fill=RAIN)
        d.ellipse((x - length * .35 - 7, y0 + length - 7, x - length * .35 + 7, y0 + length + 7), fill=RAIN)

def flake(d, cx, cy, r):
    for i in range(3):
        a = math.pi / 3 * i + math.pi / 2
        dx, dy = math.cos(a) * r, math.sin(a) * r
        d.line((cx - dx, cy - dy, cx + dx, cy + dy), fill=SNOW, width=9)
    d.ellipse((cx - 6, cy - 6, cx + 6, cy + 6), fill=SNOW)

def bolt(d):
    d.polygon([(140, 150), (100, 210), (130, 210), (112, 252), (172, 188), (140, 188), (160, 150)], fill=BOLT)

def make(name):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    if name == "clear_day": sun(d, 128, 128, 58)
    elif name == "clear_night": moon(img, 128, 128, 92)
    elif name in ("partly_day", "partly_night"):
        if name == "partly_day": sun(d, 160, 96, 46)
        else: moon(img, 176, 80, 70)
        outline_cloud(img, 26, 210, 180, CLOUD)
    elif name == "cloudy":
        cloud(d, 90, 150, 150, CLOUD2)
        outline_cloud(img, 14, 205, 190, CLOUD)
    elif name == "fog":
        cloud(d, 40, 130, 176, CLOUD2)
        for i, (a, b) in enumerate(((30, 226), (50, 206), (40, 216))):
            y = 166 + i * 30
            d.line((a, y, b, y), fill=FOG, width=16)
            d.ellipse((a - 8, y - 8, a + 8, y + 8), fill=FOG); d.ellipse((b - 8, y - 8, b + 8, y + 8), fill=FOG)
    else:
        if name == "showers_day":
            sun(d, 176, 72, 46)
            outline_cloud(img, 20, 158, 196, CLOUD); d = ImageDraw.Draw(img)
        elif name == "thunder":
            cloud(d, 20, 150, 210, DARK)
        else:
            cloud(d, 20, 150, 210, CLOUD)
        if name == "drizzle": drops(d, 3, 182, 26)
        elif name in ("rain", "showers_day"): drops(d, 3, 180, 56)
        elif name == "snow":
            for cx, cy in ((76, 192), (128, 226), (180, 192)): flake(d, cx, cy, 22)
        elif name == "sleet":
            drops(d, 2, 180, 50, [84, 188]); flake(d, 136, 214, 22)
        elif name == "thunder":
            bolt(d); drops(d, 2, 172, 40, [66, 214])
    return img

names = ["clear_day", "clear_night", "partly_day", "partly_night", "cloudy", "fog", "drizzle", "rain", "showers_day", "snow", "sleet", "thunder"]
for n in names:
    im = make(n)
    for size in (64, 30):
        im.resize((size, size), Image.LANCZOS).save(f"icons/{n}_{size}.png")
# Vorschau auf schwarz
prev = Image.new("RGBA", (len(names) * 70, 110), (0, 0, 0, 255))
for i, n in enumerate(names):
    for size, y in ((64, 4), (30, 74)):
        t = Image.open(f"icons/{n}_{size}.png"); prev.alpha_composite(t, (i * 70 + 3, y))
prev.save("icons_preview.png")
