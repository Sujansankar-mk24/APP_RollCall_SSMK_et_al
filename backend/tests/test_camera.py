"""Tests for the live drone/camera feed (app/camera)."""

import time

import cv2
import numpy as np
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.camera.live import LiveFeedManager
from app.camera.sources import UploadedClipSource
from app.database import engine
from app.main import app
from app.models import Media, MediaSource, TimelineEvent, TimelineKind

client = TestClient(app)


def make_clip(path) -> None:
    """A 2-second test video of a gray scene."""
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 15, (320, 240))
    for _ in range(30):
        writer.write(np.full((240, 320, 3), 90, dtype=np.uint8))
    writer.release()


def new_incident() -> int:
    response = client.post("/reports", data={"type": "fire", "latitude": 33.07, "longitude": -96.1})
    return response.json()["incident_id"]


def test_status_before_any_feed():
    incident_id = new_incident()
    body = client.get(f"/incidents/{incident_id}/camera").json()
    assert body["active"] is False
    assert client.get(f"/incidents/{incident_id}/camera/frame.jpg").status_code == 404


def test_unknown_incident_returns_404():
    assert client.get("/incidents/999/camera").status_code == 404


def test_feed_analyzes_frames_saves_snapshots_and_stops(tmp_path):
    clip = tmp_path / "clip.mp4"
    make_clip(clip)
    incident_id = new_incident()
    manager = LiveFeedManager()

    feed = manager.start(incident_id, UploadedClipSource([clip], label="Test camera"))
    time.sleep(1.5)
    assert feed.running and feed.frames_analyzed > 0
    assert feed.latest_jpeg and feed.latest_jpeg[:2] == b"\xff\xd8"  # a real JPEG

    manager.stop(incident_id)
    time.sleep(0.6)
    assert not feed.running

    with Session(engine) as session:
        snapshots = session.exec(select(Media).where(Media.incident_id == incident_id,
                                                     Media.source == MediaSource.camera)).all()
        events = session.exec(select(TimelineEvent).where(TimelineEvent.incident_id == incident_id,
                                                          TimelineEvent.kind == TimelineKind.camera)).all()
    assert len(snapshots) >= 1 and snapshots[0].annotated_name
    messages = [e.message for e in events]
    assert messages[0] == "Test camera started (demo footage)."
    assert any("in view" in m for m in messages)
    assert "ended" in messages[-1]
