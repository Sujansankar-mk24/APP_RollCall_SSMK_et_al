"""
The AI verification pipeline.

For every photo or video:
  1. Shrink it to a laptop-friendly size.
  2. Measure brightness; if it's dark, enhance it (low_light.py).
  3. Find people with YOLO (people.py).
  4. Look for fire and smoke (fire.py).
  4b. Flag people who may be down or are close to the flames (scene.py).
  5. Draw boxes on a copy of the image so responders can see what the AI saw.
  6. Save the results to the database and add a line to the incident timeline.

For a video, steps 1-5 run on about one frame per second, and the results are
combined (see combine_frames).

analyze_media() runs as a FastAPI "background task": the upload request returns
right away and this work happens afterwards, so the app never waits on the AI.
"""

import threading
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from sqlmodel import Session

from app.ai.detections import Detection, FireSmokeResult
from app.ai.fire import get_fire_detector
from app.ai.low_light import prepare_for_detection
from app.ai.people import get_people_detector
from app.ai.scene import label_people
from app.ai.video import sample_frames
from app.config import ANALYSIS_MAX_SIDE, ANNOTATED_DIR, MEDIA_DIR, THUMBS_DIR
from app.database import engine
from app.models import AnalysisStatus, Media, MediaKind, TimelineKind, utc_now
from app.services.timeline import add_event

THUMBNAIL_MAX_SIDE = 480

# Only one analysis at a time: the AI models are big, and running two at once
# on a laptop would just make both slower.
_analysis_lock = threading.Lock()

# Box colors (OpenCV uses Blue, Green, Red order).
BOX_COLORS = {
    "person": (255, 180, 0),            # bright blue
    "person down?": (255, 0, 255),      # magenta: stands out as "check on this person"
    "person near fire": (0, 200, 255),  # amber
    "fire": (0, 60, 255),               # red-orange
    "smoke": (200, 200, 200),           # light gray
}


@dataclass
class FrameFindings:
    """Everything the AI found in one frame."""

    people: list[Detection]
    fire: FireSmokeResult
    brightness: float
    low_light_used: bool
    annotated: np.ndarray  # the frame with boxes drawn on it
    people_down: int = 0       # people who may be lying on the ground
    people_near_fire: int = 0  # people close to the flames

    @property
    def importance(self) -> float:
        """Used to pick the single most informative frame of a video."""
        return (self.fire.fire_confidence * 2 + self.fire.smoke_confidence + 0.5 * len(self.people)
                + self.people_down + 0.5 * self.people_near_fire)


@dataclass
class MediaFindings:
    """The combined result for a whole photo or video."""

    fire_detected: bool
    fire_confidence: float
    smoke_detected: bool
    smoke_confidence: float
    people_count: int
    people_down: int
    people_near_fire: int
    low_light_used: bool
    brightness: float
    frames_analyzed: int
    best_annotated: np.ndarray
    thumbnail: np.ndarray


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def resize_to_max_side(frame: np.ndarray, max_side: int) -> np.ndarray:
    """Shrink (never enlarge) so the longest side is at most max_side pixels."""
    height, width = frame.shape[:2]
    scale = max_side / max(height, width)
    if scale >= 1:
        return frame
    return cv2.resize(frame, (int(width * scale), int(height * scale)), interpolation=cv2.INTER_AREA)


def draw_findings(frame: np.ndarray, detections: list[Detection], low_light_used: bool) -> np.ndarray:
    """Draw labeled boxes on a copy of the frame."""
    canvas = frame.copy()
    thickness = max(2, round(max(canvas.shape[:2]) / 400))
    font_scale = max(0.5, max(canvas.shape[:2]) / 1400)

    for detection in detections:
        color = BOX_COLORS.get(detection.label, (255, 255, 255))
        x1, y1, x2, y2 = detection.box
        cv2.rectangle(canvas, (x1, y1), (x2, y2), color, thickness)

        # Label with a filled background so it's readable on any image.
        text = f"{detection.label} {detection.confidence:.0%}"
        (text_w, text_h), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, font_scale, 1)
        label_top = max(y1 - text_h - baseline - 4, 0)
        cv2.rectangle(canvas, (x1, label_top), (x1 + text_w + 6, label_top + text_h + baseline + 4), color, -1)
        cv2.putText(canvas, text, (x1 + 3, label_top + text_h + 2), cv2.FONT_HERSHEY_SIMPLEX,
                    font_scale, (0, 0, 0), 1, cv2.LINE_AA)

    if low_light_used:
        cv2.putText(canvas, "LOW-LIGHT ENHANCED", (10, int(30 * font_scale / 0.5)), cv2.FONT_HERSHEY_SIMPLEX,
                    font_scale, (0, 255, 255), max(1, thickness // 2), cv2.LINE_AA)
    return canvas


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def analyze_frame(frame: np.ndarray, next_frame: Optional[np.ndarray] = None) -> FrameFindings:
    """Run every detector on one frame."""
    frame = resize_to_max_side(frame, ANALYSIS_MAX_SIDE)
    if next_frame is not None:
        next_frame = resize_to_max_side(next_frame, ANALYSIS_MAX_SIDE)

    # People are found on the (possibly brightened) image...
    enhanced, brightness, low_light_used = prepare_for_detection(frame)
    people = get_people_detector().detect(enhanced)

    # ...but fire is judged on the original colors, because brightening
    # changes colors and flames are already bright. Knowing where people
    # are lets it ignore flame-colored safety gear.
    fire = get_fire_detector().detect(frame, next_frame, people)

    # Who might need help first?
    labeled_people, people_down, people_near_fire = label_people(people, fire.boxes)

    annotated = draw_findings(enhanced, labeled_people + fire.boxes, low_light_used)
    return FrameFindings(people, fire, brightness, low_light_used, annotated, people_down, people_near_fire)


def combine_frames(frames: list[FrameFindings], thumbnail: np.ndarray) -> MediaFindings:
    """
    Combine per-frame results into one answer for the whole video:
      * fire/smoke: must show up in at least 2 sampled frames (1 for very short
        clips), so a single odd frame doesn't trigger a false alarm.
      * confidence: the highest confidence seen.
      * people: the most people seen in any single frame (the same people
        appear in many frames, so adding them up would over-count).
    """
    needed = 1 if len(frames) <= 3 else 2
    fire_frames = [f for f in frames if f.fire.fire_detected]
    smoke_frames = [f for f in frames if f.fire.smoke_detected]
    best = max(frames, key=lambda f: f.importance)

    return MediaFindings(
        fire_detected=len(fire_frames) >= needed,
        fire_confidence=max((f.fire.fire_confidence for f in fire_frames), default=0.0),
        smoke_detected=len(smoke_frames) >= needed,
        smoke_confidence=max((f.fire.smoke_confidence for f in smoke_frames), default=0.0),
        people_count=max(len(f.people) for f in frames),
        people_down=max(f.people_down for f in frames),
        people_near_fire=max(f.people_near_fire for f in frames),
        low_light_used=any(f.low_light_used for f in frames),
        brightness=round(sum(f.brightness for f in frames) / len(frames), 1),
        frames_analyzed=len(frames),
        best_annotated=best.annotated,
        thumbnail=thumbnail,
    )


def analyze_file(path: Path, kind: MediaKind) -> MediaFindings:
    """Analyze a photo or video file on disk."""
    if kind == MediaKind.photo:
        image = cv2.imread(str(path))  # also applies the phone's rotation (EXIF) setting
        if image is None:
            raise ValueError("Could not read this image file.")
        return combine_frames([analyze_frame(image)], thumbnail=image)

    frames: list[FrameFindings] = []
    raw_frames: list[np.ndarray] = []
    for frame, next_frame in sample_frames(path):
        frames.append(analyze_frame(frame, next_frame))
        raw_frames.append(resize_to_max_side(frame, THUMBNAIL_MAX_SIDE))
    if not frames:
        raise ValueError("This video has no readable frames.")
    # The gallery preview for a video is its middle sampled frame.
    return combine_frames(frames, thumbnail=raw_frames[len(raw_frames) // 2])


def describe(media: Media) -> str:
    """Plain-English summary for the incident timeline."""
    what = media.kind.value
    found = []
    if media.fire_detected:
        found.append(f"fire ({media.fire_confidence:.0%})")
    if media.smoke_detected:
        found.append(f"smoke ({media.smoke_confidence:.0%})")
    if media.people_count:
        found.append(f"{media.people_count} {'person' if media.people_count == 1 else 'people'}")
    if media.people_down:
        found.append(f"{media.people_down} may be down")
    if media.people_near_fire:
        found.append(f"{media.people_near_fire} near the flames")

    message = f"AI checked {what}: " + (", ".join(found) + " detected" if found else "no fire, smoke or people detected")
    if media.low_light_used:
        message += " (low-light enhancement used)"
    return message + "."


def analyze_media(media_id: int, event_time: Optional[datetime] = None) -> None:
    """
    Analyze one saved Media row and store the results.

    Runs in the background after an upload. `event_time` is only passed by the
    demo seed script, to place the timeline entry at a realistic past time.
    """
    with _analysis_lock, Session(engine) as session:
        media = session.get(Media, media_id)
        if media is None:
            return

        media.analysis_status = AnalysisStatus.processing
        session.add(media)
        session.commit()

        try:
            findings = analyze_file(MEDIA_DIR / media.file_name, media.kind)

            # Save the annotated image and the gallery thumbnail.
            annotated_path = ANNOTATED_DIR / f"{media.id}.jpg"
            cv2.imwrite(str(annotated_path), findings.best_annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
            thumb_path = THUMBS_DIR / f"{media.id}.jpg"
            cv2.imwrite(str(thumb_path), resize_to_max_side(findings.thumbnail, THUMBNAIL_MAX_SIDE),
                        [cv2.IMWRITE_JPEG_QUALITY, 80])

            media.annotated_name = annotated_path.relative_to(MEDIA_DIR).as_posix()
            media.thumbnail_name = thumb_path.relative_to(MEDIA_DIR).as_posix()
            media.fire_detected = findings.fire_detected
            media.fire_confidence = findings.fire_confidence
            media.smoke_detected = findings.smoke_detected
            media.smoke_confidence = findings.smoke_confidence
            media.people_count = findings.people_count
            media.people_down = findings.people_down
            media.people_near_fire = findings.people_near_fire
            media.low_light_used = findings.low_light_used
            media.brightness = findings.brightness
            media.frames_analyzed = findings.frames_analyzed
            media.fire_detector = get_fire_detector().name
            media.analysis_status = AnalysisStatus.done
            media.analyzed_at = event_time or utc_now()
            add_event(session, media.incident_id, TimelineKind.ai_result, describe(media), at=event_time)
        except Exception as error:  # never let one bad file crash the server
            traceback.print_exc()
            media.analysis_status = AnalysisStatus.failed
            media.analysis_error = str(error)
            media.analyzed_at = event_time or utc_now()
            add_event(session, media.incident_id, TimelineKind.ai_result,
                      f"AI could not analyze this {media.kind.value}: {error}", at=event_time)

        session.add(media)
        session.commit()
