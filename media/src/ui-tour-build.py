#!/usr/bin/env python3
"""Build the annotated README feature tour from the raw recording.

  python3 media/src/ui-tour-build.py

Reads media/ui.mp4 (see ui-tour-record.sh) plus the beats and geometry files it
writes, then adds a camera (smooth zoom/pan), highlight rings on the UI element
each beat is about, and floating callout bubbles -- writing media/ui-tour.gif.

Everything is expressed in *logical* pixels relative to the window's top-left, so
the monitor's scale factor does not matter: the recorder writes the scale and the
desktop margin it filmed, and we convert to source pixels here. The window itself
is a fixed 720x560 logical.

The beats file records times relative to the moment recording "really" started;
the recorder has a little start-up latency, so we calibrate the offset against
the video itself by detecting the first frame the search box appears on.
"""
import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "media", "ui.mp4")
TMP = os.environ.get("TMPDIR", "/tmp")
BEATS = os.path.join(TMP, "omaset-ui-tour-beats.txt")
GEOM = os.path.join(TMP, "omaset-ui-tour-geometry.txt")
WORK = "/tmp/opencode/tourbuild"
FRAMES = os.path.join(WORK, "src")
OUTDIR = os.path.join(WORK, "out")
ACCENT = "#f38d70"
FG = "#e6d9db"
FONT_R = "JetBrainsMono-NF-Regular"
FONT_B = "JetBrainsMono-NF-Bold"

FPS = 8
OW, OH = 800, 622                # output size (7:9, a touch larger for legibility)
WIN_W, WIN_H = 720, 560          # the omaset window, logical px

# UI rectangles, logical px from the window's top-left. The sidebar is ~191px
# wide, the content column runs 191..692, and each setting row is ~45px tall.
SEARCHBOX = (191, 42, 501, 30)
ROUNDING_ROW = (191, 434, 501, 45)
BADGE = (648, 540, 75, 20)
CHANGED_ITEM1 = (191, 40, 501, 44)
CHANGED_ITEM2 = (191, 88, 501, 44)
JUMPED_ROW = (191, 94, 501, 45)

# The search push-in frames the content pane symmetrically: wide enough to keep a
# little padding right up to the window's right edge, but starting past every
# sidebar label (the longest ends near x=110), so nothing is ever sliced in half.
SEARCH_CX, SEARCH_CY, SEARCH_W = 441.5, 190, 557

BUBBLE_Y = 520


def run(args, **kw):
    subprocess.run(args, check=True, **kw)


def magick(*args):
    run(["magick", *args])


def smoothstep(a, b, x):
    if b == a:
        return 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def img_size(path):
    out = subprocess.run(["magick", "identify", "-format", "%w %h", path],
                         capture_output=True, text=True).stdout.split()
    return int(out[0]), int(out[1])


def mean_region(path, box):
    out = subprocess.run(
        ["magick", path, "-crop", f"{box[2]}x{box[3]}+{box[0]}+{box[1]}",
         "+repage", "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"],
        capture_output=True, text=True).stdout
    return float(out)


# ---------------------------------------------------------------- calibration
def read_beats():
    beats = {}
    with open(BEATS) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) == 2:
                beats[parts[1]] = float(parts[0])
    return beats


def read_geom():
    """Logical margin of desktop around the window, and the monitor scale."""
    with open(GEOM) as fh:
        margin, scale = fh.read().split()
    return float(margin), float(scale)


def to_src(box, margin, scale):
    """Logical window-local rect -> source (physical) rect."""
    return (int((box[0] + margin) * scale), int((box[1] + margin) * scale),
            int(box[2] * scale), int(box[3] * scale))


def detect_search(files, box):
    """Video time the search box first appears (empty box -> accent-outlined)."""
    ref = mean_region(files[int(1.0 * FPS) - 1], box)
    hits = 0
    for i, f in enumerate(files):
        if abs(mean_region(f, box) - ref) > 0.010:
            hits += 1
            if hits >= 2:
                return (i - 1 + 0.5) / FPS
        else:
            hits = 0
    return 5.4


# ---------------------------------------------------------------- camera
def build_camera(beats, margin):
    t0 = detect_search(FRAMES_FILES, SEARCH_SRC) - (beats["search"] - 0.7)
    A = lambda name: beats[name] + t0            # noqa: E731
    S = A("search") - 0.7        # the "/" opens search
    R1 = A("typed")              # Return jumps to the matching setting
    A0 = A("row")                # adjust begins
    A1 = A0 + 2.6                # adjust ends (10 x l)
    C = A("adjusted") + 1.1      # the Changed list opens
    J = A("changed")             # j selects the next entry
    R2 = A("selected")           # Return jumps to that setting
    E = A("end")

    # The window floats in a slice of the desktop for the whole tour, so its
    # border and rounded corners have something to read against. Only the search
    # pushes in on the pane; everything else holds wide, because the view has to
    # stay wide enough to actually watch the corners round off and to see the
    # Changed list as a whole.
    wide = WIN_W + 2 * margin
    cam = [
        (0.0,      WIN_W / 2, WIN_H / 2, wide),
        (S - 0.6,  WIN_W / 2, WIN_H / 2, wide),
        (S + 0.5,  SEARCH_CX, SEARCH_CY, SEARCH_W),
        (R1 - 0.4, SEARCH_CX, SEARCH_CY, SEARCH_W),
        (R1 + 0.6, WIN_W / 2, WIN_H / 2, wide),   # back out, corners visible
        (E,        WIN_W / 2, WIN_H / 2, wide),
    ]
    return cam, dict(S=S, R1=R1, A0=A0, A1=A1, C=C, J=J, R2=R2, E=E), t0


def camera_at(cam, t):
    if t <= cam[0][0]:
        _, cx, cy, w = cam[0]
    elif t >= cam[-1][0]:
        _, cx, cy, w = cam[-1]
    else:
        for i in range(len(cam) - 1):
            t0, x0, y0, w0 = cam[i]
            t1, x1, y1, w1 = cam[i + 1]
            if t0 <= t <= t1:
                e = smoothstep(t0, t1, t)
                cx, cy, w = (x0 + (x1 - x0) * e, y0 + (y1 - y0) * e,
                             w0 + (w1 - w0) * e)
                break
    return cx, cy, w


def crop_of(cam_v, margin, scale, src_w, src_h):
    """Logical framing -> integer source-pixel crop, clamped to the frame."""
    cx, cy, rw = cam_v
    rh = rw * OH / OW
    x = (cx - rw / 2 + margin) * scale
    y = (cy - rh / 2 + margin) * scale
    w = min(rw * scale, src_w)
    h = min(rh * scale, src_h)
    x = int(round(max(0.0, min(x, src_w - w))))
    y = int(round(max(0.0, min(y, src_h - h))))
    return x, y, int(round(w)), int(round(h))


def to_out(box, crop, margin, scale):
    """Logical window-local rect -> output-pixel rect for the current crop."""
    x0, y0, w, h = crop
    sx, sy = OW / w, OH / h
    return ((box[0] + margin) * scale - x0) * sx, ((box[1] + margin) * scale - y0) * sy, box[2] * scale * sx, box[3] * scale * sy


# ---------------------------------------------------------------- bubbles
def bubble_png(text, big, path):
    ps = 24 if big else 17
    cw = ps * 0.62
    pad = 24
    w = int(pad * 2 + len(text) * cw)
    h = ps + 30
    r = h // 2
    magick("-size", f"{w}x{h}", "xc:none",
           "-fill", "#211b1bee", "-stroke", ACCENT, "-strokewidth", "2",
           "-draw", f"roundrectangle 1,1,{w-2},{h-2},{r},{r}",
           "-font", FONT_B if big else FONT_R, "-pointsize", str(ps),
           "-fill", FG, "-stroke", "none", "-gravity", "center",
           "-annotate", "+0+0", text, path)
    return w, h


def main():
    global FRAMES_FILES, SEARCH_SRC
    for d in (FRAMES, OUTDIR):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d, exist_ok=True)

    run(["ffmpeg", "-v", "error", "-i", SRC, "-vf", f"fps={FPS}",
         os.path.join(FRAMES, "s_%04d.png")])
    FRAMES_FILES = sorted(os.path.join(FRAMES, f) for f in os.listdir(FRAMES)
                          if f.endswith(".png"))
    SRC_W, SRC_H = img_size(FRAMES_FILES[0])

    margin, scale = read_geom()
    SEARCH_SRC = to_src(SEARCHBOX, margin, scale)
    beats = read_beats()
    cam, T, t0 = build_camera(beats, margin)
    print(f"t0={t0:.2f}s  src={SRC_W}x{SRC_H} margin={margin:g} scale={scale:g}")
    print("  " + "  ".join(f"{k}={v:.1f}" for k, v in T.items()))

    n = len(FRAMES_FILES)
    print(f"frames: {n} @ {FPS}fps -> {OW}x{OH}")

    # overlays, in absolute video time. The search gets no ring: the camera has
    # already pushed in on it, so a second box on top would be redundant.
    overlays = [
        {"k": "bubble", "text": "Every Omarchy setting. One window.",
         "t": (0.5, T["S"] - 0.4), "big": True},
        {"k": "bubble", "text": "/  search any setting",
         "t": (T["S"] + 0.45, T["R1"] - 0.15)},
        {"k": "ring", "rect": ROUNDING_ROW, "t": (T["R1"] + 0.35, T["A1"] + 0.4)},
        {"k": "bubble", "text": "h / l  adjust",
         "t": (T["A0"] + 0.4, T["A1"] + 0.5)},
        {"k": "ring", "rect": BADGE, "t": (T["A1"] + 0.5, T["C"] + 0.2)},
        {"k": "bubble", "text": "every change is tracked",
         "t": (T["A1"] + 0.3, T["C"] - 0.2)},
        {"k": "ring", "rect": CHANGED_ITEM1, "t": (T["C"] + 0.3, T["J"] + 0.2)},
        {"k": "bubble", "text": "c  what differs from stock",
         "t": (T["C"] + 0.45, T["J"] - 0.1)},
        {"k": "ring", "rect": CHANGED_ITEM2, "t": (T["J"] + 0.3, T["R2"] - 0.1)},
        {"k": "bubble", "text": "\u23ce  jump to it",
         "t": (T["J"] + 0.35, T["R2"] + 0.35)},
        {"k": "ring", "rect": JUMPED_ROW, "t": (T["R2"] + 0.2, T["E"] - 0.1)},
        {"k": "bubble", "text": "Your dotfiles, made visible.",
         "t": (T["R2"] + 0.4, T["E"] - 0.15)},
    ]

    for idx, o in enumerate(overlays):
        if o["k"] == "bubble":
            o["png"] = os.path.join(WORK, f"b{idx:02d}.png")
            o["bw"], o["bh"] = bubble_png(o["text"], o.get("big", False), o["png"])

    for i in range(1, n + 1):
        t = (i - 0.5) / FPS
        src = FRAMES_FILES[i - 1]
        crop = crop_of(camera_at(cam, t), margin, scale, SRC_W, SRC_H)
        x, y, w, h = crop
        args = [src, "-crop", f"{w}x{h}+{x}+{y}", "+repage",
                "-resize", f"{OW}x{OH}!"]

        for o in overlays:
            if o["k"] == "ring" and o["t"][0] <= t <= o["t"][1]:
                rx, ry, rw, rh = to_out(o["rect"], crop, margin, scale)
                args += ["-fill", "none", "-stroke", ACCENT, "-strokewidth", "2",
                         "-draw",
                         f"roundrectangle {rx:.1f},{ry:.1f} {rx+rw:.1f},{ry+rh:.1f} 10,10"]

        for o in overlays:
            if o["k"] != "bubble":
                continue
            a, b = o["t"]
            if not (a - 0.05 <= t <= b + 0.05):
                continue
            op = smoothstep(a, a + 0.25, t) * (1 - smoothstep(b - 0.25, b, t))
            if op <= 0.01:
                continue
            bx = (OW - o["bw"]) // 2
            args += ["(", o["png"], "-alpha", "set", "-channel", "A",
                     "-evaluate", "multiply", f"{op:.3f}", "+channel", ")",
                     "-gravity", "northwest", "-geometry", f"+{bx}+{BUBBLE_Y}",
                     "-compose", "over", "-composite"]

        args.append(os.path.join(OUTDIR, f"f_{i:04d}.png"))
        magick(*args)
        if i % 40 == 0:
            print(f"  {i}/{n}")

    gif = os.path.join(ROOT, "media", "ui-tour.gif")
    delay = max(1, round(100 / FPS))
    magick("-delay", str(delay), "-loop", "0",
           os.path.join(OUTDIR, "f_*.png"),
           "+dither", "-colors", "64", "-fuzz", "0.8%",
           "-layers", "Optimize", gif)
    print("wrote", gif, f"{os.path.getsize(gif)//1024} KB")


if __name__ == "__main__":
    FRAMES_FILES = []
    SEARCH_SRC = (0, 0, 0, 0)
    main()
