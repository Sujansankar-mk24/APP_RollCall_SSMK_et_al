"""
Turn simulator screen recordings + the walkthrough's event log into one
finished video: the phone on the left, captions on the right ("what is being
shown" and "what I'm doing"), a ring wherever a tap happens, a progress strip
of the scenes, and a voice-over (macOS's built-in Samantha voice).

Normally run by tools/record_demo.sh. By hand:
    backend/.venv/bin/python tools/make_demo_video.py \
        --clip work/clip1.mov work/events1.jsonl <time recording 1 stopped> \
        --clip work/clip2.mov work/events2.jsonl <time recording 2 stopped> \
        --out demo_video/RescueSight-walkthrough.mp4

Needs: Python packages numpy, opencv, pillow, imageio-ffmpeg (all in the
backend's requirements) and macOS (for the `say` voice).
"""

import argparse
import json
import subprocess
import tempfile
import wave
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
FPS = 30
W, H = 1920, 1080
PHONE_H = 1000                      # phone picture height on the canvas
PHONE_W = round(1206 * PHONE_H / 2622)
PHONE_X, PHONE_Y = 130, 40
POINTS_W, POINTS_H = 402, 874       # the simulated iPhone's screen in points
PANEL_X, PANEL_W = 720, 1110
VOICE, VOICE_RATE = "Samantha", 185
AUDIO_RATE = 22050

BG = (17, 14, 11)                   # BGR for OpenCV (a deep blue-black)
SCENES = ["Map", "Night mode", "Incident details", "Drone feed", "Priority & actions",
          "Severe weather", "Reporting", "Incidents tab", "Offline"]
# Shorter names for the progress strip at the bottom, so all nine fit.
CHIPS = ["Map", "Night mode", "Details", "Drone", "Priority", "Weather", "Report", "Incidents", "Offline"]

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, width: int) -> list[str]:
    """Split text into lines that fit `width` pixels."""
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


# ---------------------------------------------------------------------------
# Events and timing
# ---------------------------------------------------------------------------

@dataclass
class Caption:
    start: float          # seconds into the clip
    scene: int
    headline: str
    detail: str
    doing: str


@dataclass
class Clip:
    video: Path
    events: list[dict]
    record_start: float   # wall-clock time the recording started
    captions: list[Caption] = field(default_factory=list)
    taps: list[tuple[float, float, float]] = field(default_factory=list)            # (t, x, y) in points
    swipes: list[tuple[float, float, float, float, float]] = field(default_factory=list)
    begin: float = 0.0
    end: float = 0.0

    def load(self) -> None:
        rel = lambda e: e["t"] - self.record_start
        for e in self.events:
            if e["k"] == "cap":
                self.captions.append(Caption(rel(e), e["scene"], e["headline"], e["detail"], e["doing"]))
            elif e["k"] == "tap":
                self.taps.append((rel(e), e["x"], e["y"]))
            elif e["k"] == "swipe":
                self.swipes.append((rel(e), e["x1"], e["y1"], e["x2"], e["y2"]))
        starts = [rel(e) for e in self.events if e["k"] == "start"]
        ends = [rel(e) for e in self.events if e["k"] == "end"]
        self.begin = max((starts[0] if starts else 0) - 0.4, 0)
        self.end = (ends[-1] if ends else rel(self.events[-1])) + 2.5


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

def panel_image(caption: Caption | None) -> np.ndarray:
    """The right-hand side for one caption (rendered once, reused every frame)."""
    img = Image.new("RGB", (W, H), BG[::-1])
    d = ImageDraw.Draw(img)
    x = PANEL_X
    d.text((x, 70), "RESCUESIGHT  ·  APP WALKTHROUGH", font=font(24, "Semibold"), fill=(139, 147, 161))
    if caption is None:
        return np.array(img)[:, :, ::-1].copy()

    scene_name = SCENES[caption.scene - 1] if 1 <= caption.scene <= len(SCENES) else ""
    d.text((x + PANEL_W - 10, 70), f"Part {caption.scene} of {len(SCENES)}", font=font(24, "Semibold"),
           fill=(139, 147, 161), anchor="ra")

    # Scene tag
    tag_font = font(26, "Bold")
    tag_w = d.textlength(scene_name.upper(), font=tag_font) + 36
    d.rounded_rectangle((x, 120, x + tag_w, 166), radius=23, fill=(29, 78, 216))
    d.text((x + 18, 143), scene_name.upper(), font=tag_font, fill=(255, 255, 255), anchor="lm")

    # Headline and explanation
    y = 200
    for line in wrap(d, caption.headline, font(64, "Bold"), PANEL_W):
        d.text((x, y), line, font=font(64, "Bold"), fill=(255, 255, 255))
        y += 78
    y += 18
    detail_font = font(36)
    for line in wrap(d, caption.detail, detail_font, PANEL_W)[:8]:
        d.text((x, y), line, font=detail_font, fill=(201, 209, 220))
        y += 50

    # What I'm doing
    if caption.doing:
        y = max(y + 36, 760)
        d.text((x, y), "WHAT I'M DOING", font=font(24, "Bold"), fill=(251, 191, 36))
        y += 40
        d.rounded_rectangle((x, y + 6, x + 8, y + 46), radius=4, fill=(251, 191, 36))
        for line in wrap(d, caption.doing, font(38, "Semibold"), PANEL_W - 30)[:2]:
            d.text((x + 28, y), line, font=font(38, "Semibold"), fill=(255, 255, 255))
            y += 50

    # Progress strip: done, current, upcoming
    sx, sy = x, 990
    chip_font = font(20, "Semibold")
    for i, name in enumerate(CHIPS, start=1):
        cw = d.textlength(name, font=chip_font) + 28
        if sx + cw > x + PANEL_W:
            break
        if i == caption.scene:
            d.rounded_rectangle((sx, sy, sx + cw, sy + 36), radius=18, fill=(29, 78, 216))
            color = (255, 255, 255)
        elif i < caption.scene:
            d.rounded_rectangle((sx, sy, sx + cw, sy + 36), radius=18, fill=(45, 52, 64))
            color = (190, 197, 208)
        else:
            d.rounded_rectangle((sx, sy, sx + cw, sy + 36), radius=18, outline=(70, 78, 92), width=2)
            color = (120, 128, 142)
        d.text((sx + 14, sy + 18), name, font=chip_font, fill=color, anchor="lm")
        sx += cw + 10
    return np.array(img)[:, :, ::-1].copy()


def card_image(title: str, subtitle: str, lines: list[str]) -> np.ndarray:
    """A full-screen title card (intro / outro)."""
    img = Image.new("RGB", (W, H), BG[::-1])
    d = ImageDraw.Draw(img)
    d.text((W // 2, 330), title, font=font(110, "Bold"), fill=(255, 255, 255), anchor="mm")
    d.text((W // 2, 440), subtitle, font=font(44, "Medium"), fill=(201, 209, 220), anchor="mm")
    y = 560
    for line in lines:
        d.text((W // 2, y), line, font=font(34), fill=(160, 168, 182), anchor="mm")
        y += 56
    return np.array(img)[:, :, ::-1].copy()


def phone_mask() -> np.ndarray:
    mask = Image.new("L", (PHONE_W, PHONE_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, PHONE_W - 1, PHONE_H - 1), radius=58, fill=255)
    return (np.array(mask)[:, :, None] / 255.0).astype(np.float32)


MASK = None


def place_phone(canvas: np.ndarray, phone: np.ndarray) -> None:
    global MASK
    if MASK is None:
        MASK = phone_mask()
    region = canvas[PHONE_Y:PHONE_Y + PHONE_H, PHONE_X:PHONE_X + PHONE_W].astype(np.float32)
    blended = phone.astype(np.float32) * MASK + region * (1 - MASK)
    canvas[PHONE_Y:PHONE_Y + PHONE_H, PHONE_X:PHONE_X + PHONE_W] = blended.astype(np.uint8)
    # A thin bezel around the screen
    cv2.rectangle(canvas, (PHONE_X - 1, PHONE_Y - 1), (PHONE_X + PHONE_W, PHONE_Y + PHONE_H), BG, 1)


def to_canvas(x: float, y: float) -> tuple[int, int]:
    """Screen points -> pixels on the canvas."""
    return (int(PHONE_X + x * PHONE_W / POINTS_W), int(PHONE_Y + y * PHONE_H / POINTS_H))


def draw_touches(canvas: np.ndarray, clip: Clip, t: float) -> None:
    overlay = canvas.copy()
    drew = False
    for (tt, x, y) in clip.taps:
        age = t - tt
        if 0 <= age <= 0.9:
            cx, cy = to_canvas(x, y)
            p = age / 0.9
            cv2.circle(overlay, (cx, cy), int(16 + 30 * p), (36, 191, 251), 5, cv2.LINE_AA)
            if age < 0.35:
                cv2.circle(overlay, (cx, cy), 14, (36, 191, 251), -1, cv2.LINE_AA)
            drew = True
    for (tt, x1, y1, x2, y2) in clip.swipes:
        age = t - tt
        if 0 <= age <= 1.3:
            p = min(age / 0.8, 1.0)
            a, b = to_canvas(x1, y1), to_canvas(x2, y2)
            cur = (int(a[0] + (b[0] - a[0]) * p), int(a[1] + (b[1] - a[1]) * p))
            cv2.line(overlay, a, cur, (36, 191, 251), 8, cv2.LINE_AA)
            cv2.circle(overlay, cur, 16, (36, 191, 251), -1, cv2.LINE_AA)
            drew = True
    if drew:
        cv2.addWeighted(overlay, 0.8, canvas, 0.2, 0, dst=canvas)


# ---------------------------------------------------------------------------
# Voice-over
# ---------------------------------------------------------------------------

def speak(text: str, workdir: Path, name: str) -> np.ndarray:
    """Text -> mono 16-bit samples at AUDIO_RATE, using macOS's `say`."""
    aiff = workdir / f"{name}.aiff"
    subprocess.run(["say", "-v", VOICE, "-r", str(VOICE_RATE), "-o", str(aiff), text], check=True)
    raw = subprocess.run([FFMPEG, "-loglevel", "error", "-i", str(aiff), "-f", "s16le", "-ac", "1",
                          "-ar", str(AUDIO_RATE), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16)


def spoken_text(c: Caption) -> str:
    doing = c.doing.rstrip(".")
    return f"{doing}. {c.detail}" if doing else c.detail


# ---------------------------------------------------------------------------
# Building the video
# ---------------------------------------------------------------------------

def read_frames(video: Path, begin: float, end: float):
    """Yield phone frames (already resized) at a steady 30 per second."""
    cmd = [FFMPEG, "-loglevel", "error", "-ss", f"{begin:.3f}", "-i", str(video), "-t", f"{end - begin:.3f}",
           "-vf", f"fps={FPS},scale={PHONE_W}:{PHONE_H}", "-f", "rawvideo", "-pix_fmt", "bgr24", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    size = PHONE_W * PHONE_H * 3
    while True:
        buf = proc.stdout.read(size)
        if len(buf) < size:
            break
        yield np.frombuffer(buf, dtype=np.uint8).reshape(PHONE_H, PHONE_W, 3)
    proc.wait()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", nargs=3, action="append", metavar=("VIDEO", "EVENTS", "RECORD_STOP"), required=True,
                        help="RECORD_STOP is the wall-clock time the recording was stopped")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    clips = []
    for video, events, stop in args.clip:
        # The simulator's recorder starts its clock at the first frame that
        # changes, not when recording begins, so work out the start from the
        # moment it was stopped and the video's length.
        _, length = imageio_ffmpeg.count_frames_and_secs(video)
        start = float(stop) - length
        clip = Clip(Path(video), [json.loads(l) for l in Path(events).read_text().splitlines() if l.strip()], start)
        clip.load()
        clips.append(clip)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="rs_video_"))
    silent = work / "silent.mp4"
    writer = subprocess.Popen(
        [FFMPEG, "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}", "-r", str(FPS),
         "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", str(silent)],
        stdin=subprocess.PIPE)

    timeline_t = 0.0                       # seconds into the finished video
    voice: list[tuple[float, str, float]] = []  # (start, text, max seconds)
    chapters: list[tuple[float, str]] = [(0.0, "Intro")]  # (start, title) for players' chapter menus

    def write(frame: np.ndarray, count: int = 1) -> None:
        nonlocal timeline_t
        for _ in range(count):
            writer.stdin.write(frame.tobytes())
            timeline_t += 1 / FPS

    def fade_card(card: np.ndarray, seconds: float) -> None:
        n = int(seconds * FPS)
        for i in range(n):
            a = min(1.0, i / 12, (n - i) / 12)
            write((card.astype(np.float32) * a + np.array(BG, np.float32) * (1 - a)).astype(np.uint8))

    # Intro
    intro = card_image("RescueSight", "Community emergency map for North Texas", [
        "App walkthrough  ·  iPhone simulator  ·  demo data",
        "AI results shown are real outputs. Drone footage is simulated and labeled that way.",
    ])
    voice.append((timeline_t + 0.4, "This is RescueSight, a community emergency map for North Texas. "
                  "Here is a walkthrough of everything the app does so far, running on an iPhone simulator with demo data.", 9.5))
    fade_card(intro, 10.0)

    for clip in clips:
        panels: dict[int, np.ndarray] = {}
        captions = clip.captions
        for i, c in enumerate(captions):
            if i == 0 or c.scene != captions[i - 1].scene:
                name = SCENES[c.scene - 1] if 1 <= c.scene <= len(SCENES) else "Part"
                chapters.append((max(timeline_t + c.start - clip.begin - 0.5, 0), f"{c.scene}. {name}"))
            nxt = captions[i + 1].start if i + 1 < len(captions) else clip.end
            voice.append((timeline_t + (c.start - clip.begin) + 0.15, spoken_text(c), max(nxt - c.start - 0.2, 1.0)))
        frame_index = 0
        for phone in read_frames(clip.video, clip.begin, clip.end):
            t = clip.begin + frame_index / FPS
            frame_index += 1
            current = None
            for i, c in enumerate(captions):
                if c.start <= t + 0.05:
                    current = i
            if current not in panels:
                panels[current] = panel_image(captions[current] if current is not None else None)
            canvas = panels[current].copy()
            place_phone(canvas, phone)
            draw_touches(canvas, clip, t)
            write(canvas)

    # Outro
    chapters.append((timeline_t, "Coming next"))
    outro = card_image("Coming next", "The rest of the build", [
        "About tab, app icon and final polish",
        "Hardware add-on: ESP32-CAM video + MLX90640 thermal camera, fused by the AI",
        "Buzzer and LED alerts when a person or fire is confirmed by two sensors",
    ])
    voice.append((timeline_t + 0.4, "Coming next: the About tab and final polish, then the hardware add-on, which pairs "
                  "a camera with a thermal sensor so the AI can confirm people and fire with two sensors.", 9.5))
    fade_card(outro, 10.0)

    writer.stdin.close()
    writer.wait()

    # Voice-over: generate each line and place it at its time.
    total = np.zeros(int((timeline_t + 2) * AUDIO_RATE), dtype=np.float32)
    for i, (start, text, limit) in enumerate(voice):
        samples = speak(text, work, f"line{i}").astype(np.float32)
        length = len(samples) / AUDIO_RATE
        if length > limit + 0.6:
            print(f"  note: line {i} is {length:.1f}s but has {limit:.1f}s: \"{text[:50]}...\"")
        at = int(start * AUDIO_RATE)
        end = min(at + len(samples), len(total))
        total[at:end] += samples[:end - at]
    total = np.clip(total, -32768, 32767).astype(np.int16)
    narration = work / "voice.wav"
    with wave.open(str(narration), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(AUDIO_RATE)
        w.writeframes(total.tobytes())

    # Chapter markers, so viewers can jump to a part (QuickTime: View > Show Chapters).
    meta = [";FFMETADATA1"]
    for i, (start, title) in enumerate(chapters):
        end = chapters[i + 1][0] if i + 1 < len(chapters) else timeline_t
        meta += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={int(start * 1000)}", f"END={int(end * 1000)}", f"title={title}"]
    metadata = work / "chapters.txt"
    metadata.write_text("\n".join(meta) + "\n")

    subprocess.run([FFMPEG, "-loglevel", "error", "-y", "-i", str(silent), "-i", str(narration), "-i", str(metadata),
                    "-map", "0:v", "-map", "1:a", "-map_chapters", "2",
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", str(out)],
                   check=True)
    for start, title in chapters:
        print(f"  {int(start // 60)}:{int(start % 60):02d}  {title}")
    print(f"Done: {out}  ({timeline_t / 60:.1f} minutes)")


if __name__ == "__main__":
    main()
