"""
Live drone feeds.

When a responder taps "Launch drone feed", a LiveFeed starts in a background
thread. It pulls frames from a camera source (sources.py) and, about 2-3
times a second, runs the same AI as uploads: people, people who may be down,
people near the flames, fire, smoke, and how much of the view is on fire.

The app shows the newest annotated frame and the numbers, updating live. Every
so often (and whenever something important changes, like more people in view)
the feed saves a snapshot to the incident, with a timeline entry, so there is
a record even after the feed stops.
"""

import threading
import time
import traceback
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

import cv2
import numpy as np
from sqlmodel import Session

from app.ai.fire import get_fire_detector
from app.ai.pipeline import THUMBNAIL_MAX_SIDE, FrameFindings, analyze_frame, resize_to_max_side
from app.camera.sources import CameraSource, default_source
from app.config import (
    ANNOTATED_DIR,
    LIVE_ANALYSES_PER_SECOND,
    LIVE_MAX_MINUTES,
    LIVE_SNAPSHOT_SECONDS,
    MEDIA_DIR,
    THUMBS_DIR,
    UPLOADS_DIR,
)
from app.database import engine
from app.models import AnalysisStatus, Media, MediaKind, MediaSource, TimelineKind, utc_now
from app.services.timeline import add_event


@dataclass
class LiveStats:
    """What the AI sees in the feed right now."""

    people_count: int = 0
    people_down: int = 0
    people_near_fire: int = 0
    fire_detected: bool = False
    fire_confidence: float = 0.0
    fire_coverage: float = 0.0   # share of the view that is flames, 0.0 to 1.0
    smoke_detected: bool = False
    low_light_used: bool = False


@dataclass
class LiveFeed:
    incident_id: int
    source: CameraSource
    started_at: datetime = field(default_factory=utc_now)
    frames_analyzed: int = 0
    stats: LiveStats = field(default_factory=LiveStats)
    # The most seen at once since the feed started.
    peak_people: int = 0
    peak_people_down: int = 0
    peak_people_near_fire: int = 0
    fire_seen: bool = False
    snapshots_saved: int = 0
    latest_jpeg: Optional[bytes] = None
    error: Optional[str] = None
    running: bool = True
    _stop: threading.Event = field(default_factory=threading.Event)
    _last_snapshot: float = 0.0

    def stop(self) -> None:
        self._stop.set()

    # ---- the background loop ---------------------------------------------

    def run(self) -> None:
        interval = 1 / LIVE_ANALYSES_PER_SECOND
        deadline = time.monotonic() + LIVE_MAX_MINUTES * 60
        last_analysis = 0.0
        recent: deque[np.ndarray] = deque(maxlen=4)  # last few frames, for the flicker check
        try:
            for frame in self.source.frames():
                if self._stop.is_set() or time.monotonic() > deadline:
                    break
                recent.append(frame)
                now = time.monotonic()
                if now - last_analysis < interval:
                    continue
                last_analysis = now
                # Compare with a frame ~0.1 s earlier to see if flames flicker.
                earlier = recent[0] if len(recent) > 1 else None
                findings = analyze_frame(frame, earlier)
                self._update(findings, frame)
        except Exception as error:  # e.g. the drone's stream dropped
            traceback.print_exc()
            self.error = str(error)
        finally:
            self.running = False
            self._record_end()

    def _update(self, findings: FrameFindings, raw_frame: np.ndarray) -> None:
        self.stats = LiveStats(
            people_count=len(findings.people),
            people_down=findings.people_down,
            people_near_fire=findings.people_near_fire,
            fire_detected=findings.fire.fire_detected,
            fire_confidence=findings.fire.fire_confidence,
            fire_coverage=round(min(findings.fire.fire_area, 1.0), 3),
            smoke_detected=findings.fire.smoke_detected,
            low_light_used=findings.low_light_used,
        )
        ok, jpeg = cv2.imencode(".jpg", findings.annotated, [cv2.IMWRITE_JPEG_QUALITY, 75])
        if ok:
            self.latest_jpeg = jpeg.tobytes()
        self.frames_analyzed += 1

        # Save a snapshot on the first frame, when something new and important
        # appears, or every LIVE_SNAPSHOT_SECONDS.
        important = (
            findings.people_down > self.peak_people_down
            or findings.people_near_fire > self.peak_people_near_fire
            or len(findings.people) > self.peak_people
            or (findings.fire.fire_detected and not self.fire_seen)
        )
        self.peak_people = max(self.peak_people, len(findings.people))
        self.peak_people_down = max(self.peak_people_down, findings.people_down)
        self.peak_people_near_fire = max(self.peak_people_near_fire, findings.people_near_fire)
        self.fire_seen = self.fire_seen or findings.fire.fire_detected

        since_last = time.monotonic() - self._last_snapshot
        if self.snapshots_saved == 0 or (important and since_last > 5) or since_last > LIVE_SNAPSHOT_SECONDS:
            self._save_snapshot(findings, raw_frame)

    # ---- records kept on the incident -------------------------------------

    def _save_snapshot(self, findings: FrameFindings, raw_frame: np.ndarray) -> None:
        """Store this moment as a camera photo on the incident, with its AI results."""
        self._last_snapshot = time.monotonic()
        name = uuid.uuid4().hex
        raw_path = UPLOADS_DIR / f"{name}.jpg"
        cv2.imwrite(str(raw_path), resize_to_max_side(raw_frame, 1280), [cv2.IMWRITE_JPEG_QUALITY, 85])

        with Session(engine) as session:
            media = Media(
                incident_id=self.incident_id,
                kind=MediaKind.photo,
                source=MediaSource.camera,
                file_name=raw_path.relative_to(MEDIA_DIR).as_posix(),
                analysis_status=AnalysisStatus.done,
                analyzed_at=utc_now(),
                fire_detected=findings.fire.fire_detected,
                fire_confidence=findings.fire.fire_confidence,
                smoke_detected=findings.fire.smoke_detected,
                smoke_confidence=findings.fire.smoke_confidence,
                people_count=len(findings.people),
                people_down=findings.people_down,
                people_near_fire=findings.people_near_fire,
                low_light_used=findings.low_light_used,
                brightness=findings.brightness,
                fire_detector=get_fire_detector().name,
                frames_analyzed=1,
            )
            session.add(media)
            session.flush()

            annotated_path = ANNOTATED_DIR / f"{media.id}.jpg"
            thumb_path = THUMBS_DIR / f"{media.id}.jpg"
            cv2.imwrite(str(annotated_path), findings.annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
            cv2.imwrite(str(thumb_path), resize_to_max_side(raw_frame, THUMBNAIL_MAX_SIDE), [cv2.IMWRITE_JPEG_QUALITY, 80])
            media.annotated_name = annotated_path.relative_to(MEDIA_DIR).as_posix()
            media.thumbnail_name = thumb_path.relative_to(MEDIA_DIR).as_posix()
            session.add(media)

            add_event(session, self.incident_id, TimelineKind.camera, f"{self.source.label}: {self._describe()}")
            session.commit()
        self.snapshots_saved += 1

    def _describe(self) -> str:
        s = self.stats
        parts = [f"{s.people_count} {'person' if s.people_count == 1 else 'people'} in view"]
        if s.people_down:
            parts.append(f"{s.people_down} may be down")
        if s.people_near_fire:
            parts.append(f"{s.people_near_fire} near the flames")
        if s.fire_detected:
            parts.append(f"fire covers {s.fire_coverage:.0%} of the view")
        elif s.smoke_detected:
            parts.append("smoke in view")
        return ", ".join(parts) + "."

    def _record_end(self) -> None:
        minutes = max((utc_now() - self.started_at).total_seconds() / 60, 0.1)
        summary = (f"{self.source.label} ended after {minutes:.1f} min. "
                   f"Most people seen at once: {self.peak_people}"
                   + (f", up to {self.peak_people_down} possibly down" if self.peak_people_down else "")
                   + (". Fire was seen." if self.fire_seen else "."))
        if self.error:
            summary = f"{self.source.label} stopped: {self.error}"
        with Session(engine) as session:
            add_event(session, self.incident_id, TimelineKind.camera, summary)
            session.commit()


class LiveFeedManager:
    """Keeps track of running feeds (at most one per incident)."""

    def __init__(self) -> None:
        self._feeds: dict[int, LiveFeed] = {}
        self._lock = threading.Lock()

    def start(self, incident_id: int, source: Optional[CameraSource] = None) -> LiveFeed:
        with self._lock:
            current = self._feeds.get(incident_id)
            if current and current.running:
                return current
            feed = LiveFeed(incident_id=incident_id, source=source or default_source())
            self._feeds[incident_id] = feed
        with Session(engine) as session:
            kind = "demo footage" if feed.source.is_demo else "live camera"
            add_event(session, incident_id, TimelineKind.camera, f"{feed.source.label} started ({kind}).")
            session.commit()
        threading.Thread(target=feed.run, name=f"live-feed-{incident_id}", daemon=True).start()
        return feed

    def stop(self, incident_id: int) -> Optional[LiveFeed]:
        feed = self._feeds.get(incident_id)
        if feed:
            feed.stop()
        return feed

    def get(self, incident_id: int) -> Optional[LiveFeed]:
        return self._feeds.get(incident_id)

    def is_live(self, incident_id: int) -> bool:
        feed = self._feeds.get(incident_id)
        return bool(feed and feed.running)

    def stop_all(self) -> None:
        for feed in self._feeds.values():
            feed.stop()


live_feeds = LiveFeedManager()
