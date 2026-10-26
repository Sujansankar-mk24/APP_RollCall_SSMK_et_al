"""
Builds the RollCall demo video from the simulator recording.

The script has 10 parts, each spoken by one person and each a fixed length
(PARTS below). For every part this:
  * cuts that scene out of the screen recording (the tour test logs when
    each scene starts) and speeds it up or slows it down to exactly the
    part's length, or shows slides for the parts about the code and design,
  * puts it on a 1920x1080 frame with the section title, who's speaking
    (in their color) and, in one version, the lines being said.
Then it joins the parts into two videos:
    RollCall-demo.mp4        with the lines on screen
    RollCall-demo-clean.mp4  without them, for recording the voice-over

Normally run by tools/record_demo.sh. By hand:
    backend/.venv/bin/python tools/make_demo_video.py --video demo_video/work/screen.mov \\
        --events demo_video/work/events.jsonl --start <time the recording started> --out demo_video

Needs Pillow and imageio-ffmpeg (both in the backend's requirements).
"""

import argparse
import json
import subprocess
import textwrap
from dataclasses import dataclass, field
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "ios/RollCall/Fonts"
ASSETS = ROOT / "ios/RollCall/Assets.xcassets"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

W, H, FPS = 1920, 1080, 30
BG = (14, 15, 18)                       # near-black, like the app in dark mode
INK, MUTED, LINE = (244, 243, 240), (150, 150, 158), (44, 46, 52)
PHONE_H = 1000                          # the phone picture's height on the frame
PHONE_W = round(1206 * PHONE_H / 2622)  # the simulator records 1206 x 2622
CARD_W = 600                            # slides use a slightly wider card
LEFT_CENTER = 430                       # the phone/slide is centered here
PANEL_X, PANEL_W = 820, 1020            # the text panel on the right

SPEAKERS = {
    "Pranav": (229, 72, 77),    # red
    "Somesh": (245, 146, 54),   # orange
    "Sujan": (70, 190, 110),    # green
    "Prithu": (74, 144, 226),   # blue
}


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    """The app's fonts, falling back to the Mac's system font."""
    files = {"heading": ["Crature-Demo.ttf", "Animosa-ExtraBold.otf"], "body": ["Quitars.otf", "Animosa-Regular.otf"],
             "mono": []}
    for file in files[name]:
        if (FONTS / file).exists():
            return ImageFont.truetype(str(FONTS / file), size)
    if name == "mono":
        return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", size)
    return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)


# Crature's demo edition has no real numbers, commas or periods (it draws a
# placeholder circle), so those characters are drawn in Animosa instead.
NOT_IN_CRATURE = set("0123456789,.")


def heading_runs(text: str, size: int):
    """Split a heading into pieces, each with the font that can draw it."""
    crature = font("heading", size)
    animosa = ImageFont.truetype(str(FONTS / "Animosa-ExtraBold.otf"), size)
    runs = []
    for ch in text:
        f = animosa if ch in NOT_IN_CRATURE else crature
        if runs and runs[-1][1] is f:
            runs[-1][0] += ch
        else:
            runs.append([ch, f])
    return runs


def heading_length(draw, text: str, size: int) -> float:
    return sum(draw.textlength(t, font=f) for t, f in heading_runs(text, size))


def draw_heading(draw, xy, text: str, size: int, fill) -> None:
    x, y = xy
    for t, f in heading_runs(text, size):
        draw.text((x, y), t, font=f, fill=fill)
        x += draw.textlength(t, font=f)


# ---------------------------------------------------------------------------
# The script: who says what, for how long, over which footage or slides
# ---------------------------------------------------------------------------

@dataclass
class Part:
    speaker: str
    seconds: float
    title: str
    lines: str
    # What's on screen, in order: ("scene", name) is footage from the tour,
    # ("slide", name) is one of the slides below. Each gets a share of the time.
    shows: list = field(default_factory=list)
    shares: list = field(default_factory=list)   # fractions of `seconds`, one per show


PARTS = [
    Part("Pranav", 20, "The problem",
         "When a tornado warning hits North Texas, apps like Watch Duty show you where the danger is. But nobody has "
         "a list of who's still inside. The grandmother on oxygen. The neighbor without a car. In rural parts of our "
         "district, help can take a long time to arrive. So we built RollCall, to make sure no one gets left behind.",
         [("scene", "hook")], [1]),
    Part("Somesh", 14, "Live hazards on the map",
         "The Map pulls live data from the National Weather Service, NASA, NOAA and the National Hurricane Center. "
         "Official alerts are shaded, and every hazard tells you its level and what to do. Turn on your location and "
         "RollCall warns you when danger gets close.",
         [("scene", "map")], [1]),
    Part("Sujan", 12, "Reports the AI checks",
         "Anyone can report what they see, but only with a photo they just took. Before a report reaches the map, our "
         "AI checks that the photo shows the actual disaster. A picture of three people inside a bedroom labeled "
         "\"winter storm\" stays off the map.",
         [("scene", "report")], [1]),
    Part("Prithu", 6.1, "Priority you can check",
         "Responders get every incident sorted by priority, and they can see exactly why each one ranks where it does.",
         [("scene", "incidents")], [1]),
    Part("Pranav", 14, "The roll call",
         "Residents join the roll call and share what could make leaving hard. When something hits, one tap tells "
         "their buddy \"I'm safe\" or \"I need help\". They can even do it right from the Lock Screen, which updates "
         "like a live sports score.",
         [("scene", "rollcall")], [1]),
    Part("Somesh", 14, "Neighbors and buddies",
         "Neighborhoods form communities. The connections web shows who checks on whom, and you can offer to be "
         "someone's buddy right from their profile. First responders are verified: the phone reads their ID, our "
         "server looks up their agency online, and then a person approves them.",
         [("scene", "community")], [1]),
    Part("Sujan", 19, "How it's built",
         "The front end is a native iPhone app in SwiftUI. It uses MapKit for the map, Apple's Vision framework to "
         "analyze photos on the phone, and ActivityKit for the Lock Screen status. The back end is Python with "
         "FastAPI and a SQLite database. Passwords are hashed with scrypt, and sign-ins are stored in the iPhone's "
         "Keychain.",
         [("slide", "architecture"), ("slide", "code")], [0.55, 0.45]),
    Part("Prithu", 26, "How the AI decides",
         "Our AI brightens dark photos with OpenCV. Then YOLOv8 finds people, and a YOLO model trained on D-Fire, a "
         "dataset of over 21,000 fire and smoke photos, finds flames. Reports within 300 meters of each other merge "
         "into one incident. Priority isn't a black box. It's simple rules anyone can check, like a confirmed fire "
         "adding 40 points. We tested everything with {backend} backend tests and {ui} UI tests that tap through "
         "the real app.",
         [("scene", "ai"), ("slide", "tests")], [0.72, 0.28]),
    Part("Pranav", 17, "Design",
         "For design, we studied real apps like WHOOP and Phantom on Mobbin, took motion ideas from transitions.dev, "
         "designed our logo in Canva, and followed Apple's design guidelines. That means dark mode, large text and "
         "VoiceOver support, and buttons big enough to tap under stress.",
         [("slide", "design"), ("slide", "lightdark")], [0.5, 0.5]),
    Part("Somesh", 14, "Privacy and what's next",
         "Privacy is built in. You opt in, your address is shown only to your community, your phone number only to "
         "your buddy, and deleting your account deletes everything. Next, we want to add text messages for people "
         "without smartphones and work with county emergency management. RollCall. Make sure no one gets left behind.",
         [("scene", "privacy")], [1]),
]


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + ([line] if line else [])


def logo(size: int) -> Image.Image:
    path = ASSETS / "Logo.imageset/logo-dark.png"
    if not path.exists():
        path = ASSETS / "Logo.imageset/logo.png"
    image = Image.open(path).convert("RGBA")
    image.thumbnail((size, size))
    return image


def background(index: int, part: Part) -> Image.Image:
    """The frame for one part: progress dots, section title, the speaker, the logo."""
    frame = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(frame)
    color = SPEAKERS[part.speaker]

    # Progress: one dot per part, the current one filled in the speaker's color.
    for i, other in enumerate(PARTS):
        x = PANEL_X + i * 34
        fill = SPEAKERS[other.speaker] if i == index else LINE
        draw.ellipse((x, 90, x + 18, 108), fill=fill)

    draw.text((PANEL_X, 140), f"{index + 1:02d}", font=font("body", 40), fill=MUTED)
    y = 190
    for line in wrap(draw, part.title, font("heading", 92), PANEL_W):
        draw_heading(draw, (PANEL_X, y), line, 92, INK)
        y += 104

    # The speaker, as a colored tag like the app's.
    name_font = font("body", 40)
    name_w = draw.textlength(part.speaker, font=name_font)
    draw.rounded_rectangle((PANEL_X, y + 24, PANEL_X + name_w + 84, y + 92), radius=18, fill=tuple(c // 4 for c in color),
                           outline=color, width=2)
    draw.ellipse((PANEL_X + 22, y + 48, PANEL_X + 42, y + 68), fill=color)
    draw.text((PANEL_X + 58, y + 33), part.speaker, font=name_font, fill=INK)

    # Bottom: the logo and the challenge.
    mark = logo(84)
    frame.paste(mark, (PANEL_X, H - 130), mark)
    draw.text((PANEL_X + 104, H - 112), "RollCall   |   Congressional App Challenge 2026   |   TX-4",
              font=font("body", 32), fill=MUTED)
    return frame


def caption_pages(part: Part, text: str) -> list[tuple[Image.Image, float, float]]:
    """The lines being said, a few at a time, each shown for its share of the part."""
    probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    fnt = font("body", 46)
    lines = wrap(probe, text, fnt, PANEL_W)
    pages = [lines[i:i + 4] for i in range(0, len(lines), 4)]
    words = [sum(len(l.split()) for l in page) for page in pages]
    total, start, out = sum(words), 0.0, []
    for page, count in zip(pages, words):
        length = part.seconds * count / total
        image = Image.new("RGBA", (PANEL_W, 4 * 62 + 20), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        for i, line in enumerate(page):
            draw.text((0, i * 62), line, font=fnt, fill=(220, 220, 226, 255))
        out.append((image, start, start + length))
        start += length
    return out


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def card(title: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (CARD_W, PHONE_H), (26, 28, 33))
    draw = ImageDraw.Draw(image)
    draw_heading(draw, (40, 40), title, 50, INK)
    return image, draw


def box(draw, xy, heading, items, color):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=24, fill=(36, 38, 45), outline=color, width=3)
    draw_heading(draw, (x0 + 26, y0 + 20), heading, 38, INK)
    for i, item in enumerate(items):
        draw.text((x0 + 26, y0 + 76 + i * 40), item, font=font("body", 30), fill=(205, 205, 212))


def slide(name: str, shots: dict[str, Path], counts: dict[str, int]) -> Image.Image:
    if name == "architecture":
        image, draw = card("How it fits together")
        box(draw, (40, 130, 560, 410), "iPhone app", ["SwiftUI, MVVM", "MapKit map", "Vision (on the phone)",
                                                      "ActivityKit Lock Screen"], SPEAKERS["Prithu"])
        box(draw, (40, 470, 560, 750), "Backend", ["Python, FastAPI", "SQLite (SQLModel)", "scrypt passwords",
                                                  "YOLOv8 + OpenCV AI"], SPEAKERS["Sujan"])
        box(draw, (40, 810, 560, 960), "Live data", ["NWS, NASA, NOAA, NHC"], SPEAKERS["Somesh"])
        for y in (410, 750):
            draw.line((300, y + 6, 300, y + 54), fill=MUTED, width=4)
            draw.polygon([(288, y + 46), (312, y + 46), (300, y + 60)], fill=MUTED)
        return image
    if name == "code":
        image, draw = card("Real code")
        draw.text((40, 110), "backend/app/ai/verify.py", font=font("body", 30), fill=MUTED)
        code = (ROOT / "backend/app/ai/verify.py").read_text().splitlines()
        start = next(i for i, l in enumerate(code) if "if yolo_fire and media.fire_detector" in l)
        y = 170
        for line in code[start:start + 12]:
            for piece in textwrap.wrap(line.strip(), 38) or [""]:
                indent = 30 if line.startswith("            ") else 0
                fill = (126, 196, 132) if piece.lstrip().startswith("#") else (225, 225, 232)
                draw.text((40 + indent, y), piece, font=font("mono", 24), fill=fill)
                y += 36
        return image
    if name == "tests":
        image, draw = card("Tested")
        for i, (number, label) in enumerate([(counts["backend"], "backend tests (pytest)"),
                                             (counts["ui"], "UI tests that tap through the real app")]):
            y = 200 + i * 330
            draw_heading(draw, (40, y), str(number), 170, SPEAKERS["Prithu"])
            for j, line in enumerate(textwrap.wrap(label, 24)):
                draw.text((40, y + 190 + j * 44), line, font=font("body", 38), fill=INK)
        return image
    if name in ("design", "lightdark"):
        image, draw = card("Design" if name == "design" else "Light and dark")
        keys = ["rollcall_light", "community_light"] if name == "design" else ["rollcall_light", "rollcall_dark"]
        for i, key in enumerate(keys):
            if key in shots and shots[key].exists():
                shot = Image.open(shots[key]).convert("RGB").resize((250, 543))
                image.paste(shot, (40 + i * 270, 140), rounded_mask(shot.size, 26))
        notes = (["Studied WHOOP and Phantom on Mobbin", "Motion ideas from transitions.dev", "Logo made in Canva",
                  "Apple's design guidelines"] if name == "design"
                 else ["Dark mode", "Large text (Dynamic Type)", "VoiceOver labels", "Big tap targets"])
        for j, note in enumerate(notes):
            y = 720 + j * 56
            draw.ellipse((42, y + 16, 54, y + 28), fill=SPEAKERS["Pranav"])   # Quitars has no bullet character
            draw.text((70, y), note, font=font("body", 34), fill=INK)
        return image
    raise ValueError(name)


# ---------------------------------------------------------------------------
# Putting it together with ffmpeg
# ---------------------------------------------------------------------------

def run(args: list[str]) -> None:
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", *args], check=True)


def scene_windows(events_path: Path, start: float) -> dict[str, tuple[float, float]]:
    """Each scene's (start, end) in seconds into the recording."""
    events = [json.loads(line) for line in events_path.read_text().splitlines() if line.strip()]
    windows = {}
    for event, following in zip(events, events[1:]):
        windows[event["scene"]] = (event["t"] - start, following["t"] - start)
    return windows


def build_part(index: int, part: Part, video: Path, windows: dict, shots: dict, counts: dict,
               work: Path, captions: bool) -> Path:
    text = part.lines.format(backend=counts["backend"], ui=counts["ui"])
    frame_path = work / f"bg_{index}.png"
    background(index, part).save(frame_path)
    inputs = ["-loop", "1", "-t", f"{part.seconds}", "-i", str(frame_path)]
    filters, last = [], "0:v"

    # What's on the left, one show after another.
    mask_path = work / "phone_mask.png"
    rounded_mask((PHONE_W, PHONE_H), 56).save(mask_path)
    t = 0.0
    for (kind, name), share in zip(part.shows, part.shares):
        length = part.seconds * share
        if kind == "scene":
            a, b = windows[name]
            source = max(b - a, 0.5)
            # Each clip gets its own copy of the rounded-corner mask (ffmpeg
            # can use an input only once).
            inputs += ["-loop", "1", "-t", f"{length:.3f}", "-i", str(mask_path)]
            mask_input = inputs.count("-i") - 1
            inputs += ["-ss", f"{a:.3f}", "-t", f"{source:.3f}", "-i", str(video)]
            i = inputs.count("-i") - 1
            filters.append(f"[{i}:v]setpts=PTS*{length / source:.5f},fps={FPS},scale={PHONE_W}:{PHONE_H},"
                           f"format=rgba,trim=duration={length:.3f}[clip{i}];"
                           f"[{mask_input}:v]scale={PHONE_W}:{PHONE_H},format=gray,trim=duration={length:.3f}[m{i}];"
                           f"[clip{i}][m{i}]alphamerge,setpts=PTS+{t:.3f}/TB[s{i}]")
            x, y = LEFT_CENTER - PHONE_W // 2, (H - PHONE_H) // 2
        else:
            slide_path = work / f"slide_{name}.png"
            slide(name, shots, counts).save(slide_path)
            inputs += ["-loop", "1", "-t", f"{length:.3f}", "-i", str(slide_path)]
            i = inputs.count("-i") - 1
            filters.append(f"[{i}:v]format=rgba,setpts=PTS+{t:.3f}/TB[s{i}]")
            x, y = LEFT_CENTER - CARD_W // 2, (H - PHONE_H) // 2
        filters.append(f"[{last}][s{i}]overlay={x}:{y}:enable='between(t,{t:.3f},{t + length:.3f})':eof_action=pass[v{i}]")
        last = f"v{i}"
        t += length

    if captions:
        for page, (image, start, end) in enumerate(caption_pages(part, text)):
            path = work / f"cap_{index}_{page}.png"
            image.save(path)
            inputs += ["-loop", "1", "-t", f"{part.seconds}", "-i", str(path)]
            i = inputs.count("-i") - 1
            filters.append(f"[{last}][{i}:v]overlay={PANEL_X}:600:enable='between(t,{start:.3f},{end:.3f})'[c{i}]")
            last = f"c{i}"

    out = work / f"part_{index}_{'cap' if captions else 'clean'}.mp4"
    run([*inputs, "-filter_complex", ";".join(filters), "-map", f"[{last}]", "-t", f"{part.seconds}",
         "-r", str(FPS), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", str(out)])
    return out


def join(parts: list[Path], out: Path, work: Path) -> None:
    listing = work / f"{out.stem}.txt"
    listing.write_text("".join(f"file '{p.resolve()}'\n" for p in parts))
    run(["-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(out)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--start", type=float, required=True, help="when the recording started (Unix time)")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--backend-tests", type=int, default=107)
    parser.add_argument("--ui-tests", type=int, default=39)
    args = parser.parse_args()

    work = args.out / "work"
    work.mkdir(parents=True, exist_ok=True)
    windows = scene_windows(args.events, args.start)
    shots = {key: work / f"shot_{key}.png" for key in ("rollcall_light", "rollcall_dark", "community_light")}
    counts = {"backend": args.backend_tests, "ui": args.ui_tests}
    total = sum(p.seconds for p in PARTS)
    print(f"{len(PARTS)} parts, {total:.1f} seconds in all")
    for captions, name in ((True, "RollCall-demo.mp4"), (False, "RollCall-demo-clean.mp4")):
        built = [build_part(i, p, args.video, windows, shots, counts, work, captions) for i, p in enumerate(PARTS)]
        join(built, args.out / name, work)
        print(f"Saved {args.out / name}")


if __name__ == "__main__":
    main()
