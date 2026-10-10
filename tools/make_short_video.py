"""
A ~2 minute version of the walkthrough, cut from the same recordings as the
full video (tools/record_demo.sh makes those). Each part is a short window
of the recording, sped up where nothing important happens, with one caption
and one narrated sentence.

Run from the project folder after tools/record_demo.sh:
    backend/.venv/bin/python tools/make_short_video.py
Result: demo_video/RescueSight-2min.mp4
"""

import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import make_demo_video as full  # reuse the drawing and voice helpers

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "demo_video" / "work"
OUT = ROOT / "demo_video" / "RescueSight-2min.mp4"
FPS, W, H = full.FPS, full.W, full.H
MAX_SPEED = 4.0

# (clip, from second, to second, title, caption, narration, fastest allowed speed)
# Seconds are positions in the recordings (see the walkthrough's events files).
PARTS = [
    (1, 17.5, 31.0, "The map", "Every report is a zone: red active, amber responding, gray resolved.",
     "Every report in North Texas becomes a zone on the map. Red is active, amber means help is on the way, and gray is resolved.", 3),
    (1, 71.1, 94.0, "Filter by mode", "Show one kind of disaster at a time, like severe weather.",
     "Filters switch between modes, like severe weather only.", 4),
    (1, 130.8, 150.0, "Night mode", "For responders working after dark.",
     "There's a night mode for responders working after dark.", 4),
    (1, 161.5, 191.0, "Incident details", "Status, priority score, and how many people reported it.",
     "Tap an incident to see its status, its priority score, and how many people reported it.", 3),
    (1, 221.4, 245.0, "What the AI saw", "Real computer vision boxes fire, smoke and people.",
     "The AI checks every photo and video for fire, smoke and people, and draws boxes around what it found.", 3),
    (1, 270.0, 310.0, "Drone feed", "Counts people, anyone who may be down, and how much is burning. Simulated until the drone is connected.",
     "Once fire is confirmed, a drone feed counts the people in view, anyone who might be injured, and how much is on fire. "
     "Until the real drone is connected, it plays simulated footage.", 3),
    (1, 362.5, 384.0, "Why this priority?", "Simple rules anyone can check, not a black box.",
     "Priority comes from simple rules that anyone can check.", 4),
    (1, 407.7, 440.0, "Responder actions", "Mark responding or resolved, and the map updates.",
     "Responders mark incidents responding or resolved, and the map updates right away.", 4),
    (1, 445.6, 475.0, "Every kind of disaster", "Fires, floods, storms, tornadoes and more.",
     "It handles every kind of disaster, like this tornado report.", 4),
    (1, 502.9, 520.0, "Report an emergency", "The form always says: call 911 first.",
     "Anyone can report an emergency, and the form always says to call nine one one first.", 3),
    (1, 535.0, 560.0, "Where is it?", "GPS location, or search any address.",
     "Set the location by GPS, or search for any address.", 4),
    (1, 600.0, 631.0, "Add a photo", "From the library, or the camera on a real iPhone.",
     "Then add a photo and send it.", 4),
    (1, 631.6, 667.0, "Merged and checked", "Nearby reports join one incident. The AI answers in seconds.",
     "Nearby reports merge into one incident instead of duplicates, and the AI checks the photo within seconds.", 3.5),
    (1, 693.1, 730.0, "Responder view", "Key numbers and a list sorted by priority.",
     "Responders get key numbers and a list sorted by priority.", 4),
    (2, 18.8, 55.0, "If the server is down", "A clear message and a Try again button, never a crash.",
     "And if the server goes down, the app says so clearly and recovers when it's back.", 4),
]


def clip_start(stop: float, video: Path) -> float:
    _, length = imageio_ffmpeg.count_frames_and_secs(str(video))
    return stop - length


def panel(title: str, caption: str, speed: float, index: int) -> np.ndarray:
    img = Image.new("RGB", (W, H), full.BG[::-1])
    d = ImageDraw.Draw(img)
    x = full.PANEL_X
    d.text((x, 90), "RESCUESIGHT", font=full.font(26, "Semibold"), fill=(139, 147, 161))
    d.text((x + full.PANEL_W - 10, 90), f"{index} / {len(PARTS)}", font=full.font(26, "Semibold"),
           fill=(139, 147, 161), anchor="ra")
    y = 380
    for line in full.wrap(d, title, full.font(76, "Bold"), full.PANEL_W):
        d.text((x, y), line, font=full.font(76, "Bold"), fill=(255, 255, 255))
        y += 92
    y += 16
    for line in full.wrap(d, caption, full.font(42), full.PANEL_W):
        d.text((x, y), line, font=full.font(42), fill=(201, 209, 220))
        y += 58
    if speed > 1.15:   # be honest that the footage is sped up
        label = f"▶▶  {speed:.1f}× speed".replace(".0×", "×")
        f = full.font(26, "Semibold")
        w = d.textlength(label, font=f) + 32
        d.rounded_rectangle((x, 960, x + w, 1004), radius=22, fill=(45, 52, 64))
        d.text((x + 16, 982), label, font=f, fill=(201, 209, 220), anchor="lm")
    return np.array(img)[:, :, ::-1].copy()


def touches(canvas, clip_events, t, speed):
    """Tap rings / drags, timed in OUTPUT seconds so they stay visible when sped up."""
    overlay = canvas.copy()
    drew = False
    for e in clip_events:
        age = (t - e["rel"]) / speed
        if e["k"] == "tap" and 0 <= age <= 0.6:
            cx, cy = full.to_canvas(e["x"], e["y"])
            import cv2
            cv2.circle(overlay, (cx, cy), int(16 + 28 * age / 0.6), (36, 191, 251), 5, cv2.LINE_AA)
            drew = True
    if drew:
        import cv2
        cv2.addWeighted(overlay, 0.8, canvas, 0.2, 0, dst=canvas)


def main() -> None:
    clips = {
        1: (WORK / "clip1_fixed.mov", WORK / "events1.jsonl", float((WORK / "stop1.txt").read_text())),
        2: (WORK / "clip2_fixed.mov", WORK / "events2.jsonl", float((WORK / "stop2.txt").read_text())),
    }
    events = {}
    for k, (video, ev, stop) in clips.items():
        start = clip_start(stop, video)
        evs = [json.loads(l) for l in ev.read_text().splitlines() if l.strip()]
        for e in evs:
            e["rel"] = e["t"] - start
        events[k] = [e for e in evs if e["k"] == "tap"]

    work = Path(tempfile.mkdtemp(prefix="rs_short_"))
    silent = work / "silent.mp4"
    writer = subprocess.Popen(
        [full.FFMPEG, "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}",
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", str(silent)],
        stdin=subprocess.PIPE)
    t_out = 0.0
    voice = []

    def write(frame):
        nonlocal t_out
        writer.stdin.write(frame.tobytes())
        t_out += 1 / FPS

    def card(title, subtitle, lines, seconds, narration):
        voice.append((t_out + 0.3, narration))
        img = full.card_image(title, subtitle, lines)
        n = int(seconds * FPS)
        for i in range(n):
            a = min(1.0, i / 8, (n - i) / 8)
            write((img.astype(np.float32) * a + np.array(full.BG, np.float32) * (1 - a)).astype(np.uint8))

    card("RescueSight", "Community emergency map for North Texas", ["App walkthrough  ·  iPhone simulator  ·  demo data"],
         4.5, "This is RescueSight, a community emergency map for North Texas.")

    for index, (clip_no, a, b, title, caption, narration, fastest) in enumerate(PARTS, start=1):
        video = clips[clip_no][0]
        spoken = full.speak(narration, work, f"p{index}")
        talk = len(spoken) / full.AUDIO_RATE
        src = b - a
        out_len = max(talk + 0.6, src / fastest)       # long enough to hear the line
        speed = max(src / out_len, 1.0)
        if speed == 1.0:                                # line is longer than the clip: show more of it
            src = out_len
        voice.append((t_out + 0.15, narration))
        bg = panel(title, caption, speed, index)
        cmd = [full.FFMPEG, "-loglevel", "error", "-ss", f"{a:.3f}", "-i", str(video), "-t", f"{src:.3f}",
               "-vf", f"setpts=PTS/{speed:.4f},fps={FPS},scale={full.PHONE_W}:{full.PHONE_H}",
               "-f", "rawvideo", "-pix_fmt", "bgr24", "-"]
        raw = subprocess.run(cmd, capture_output=True).stdout
        frames = np.frombuffer(raw, np.uint8).reshape(-1, full.PHONE_H, full.PHONE_W, 3)
        needed = int(round(out_len * FPS))
        for i in range(needed):
            phone = frames[min(i, len(frames) - 1)]
            canvas = bg.copy()
            full.place_phone(canvas, phone)
            touches(canvas, events[clip_no], a + i / FPS * speed, speed)
            write(canvas)

    card("Coming next", "Hardware add-on", ["Camera + thermal sensor, fused by the AI to confirm people and fire"],
         5.0, "Coming next: a hardware add-on that pairs a camera with a thermal sensor.")
    writer.stdin.close()
    writer.wait()

    total = np.zeros(int((t_out + 2) * full.AUDIO_RATE), np.float32)
    for i, (start, text) in enumerate(voice):
        s = full.speak(text, work, f"v{i}").astype(np.float32)
        at = int(start * full.AUDIO_RATE)
        end = min(at + len(s), len(total))
        total[at:end] += s[:end - at]
    wav = work / "voice.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(full.AUDIO_RATE)
        w.writeframes(np.clip(total, -32768, 32767).astype(np.int16).tobytes())
    subprocess.run([full.FFMPEG, "-loglevel", "error", "-y", "-i", str(silent), "-i", str(wav), "-c:v", "copy",
                    "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", str(OUT)], check=True)
    print(f"Done: {OUT}  ({t_out / 60:.1f} minutes, {t_out:.0f} s)")


if __name__ == "__main__":
    main()
