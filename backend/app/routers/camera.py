"""
Drone / camera feed endpoints:

  GET  /incidents/{id}/camera            is a feed running, and what does the AI see?
  POST /incidents/{id}/camera/start      launch the feed (real camera if configured, else demo)
  POST /incidents/{id}/camera/stop       stop it
  GET  /incidents/{id}/camera/frame.jpg  the newest picture, with AI boxes drawn on

The app checks the status and picture a few times a second while the feed is
on screen, which looks like live video.
"""

from datetime import timezone

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session

from app.camera.live import LiveFeed, live_feeds
from app.config import CAMERA_STREAM_URL
from app.database import get_session
from app.models import Incident
from app.schemas import LiveFeedOut, LiveStatsOut

router = APIRouter(prefix="/incidents/{incident_id}/camera", tags=["camera"])


def _require_incident(session: Session, incident_id: int) -> None:
    if session.get(Incident, incident_id) is None:
        raise HTTPException(status_code=404, detail="Incident not found")


def _status(incident_id: int, feed: LiveFeed | None) -> LiveFeedOut:
    if feed is None:
        return LiveFeedOut(active=False, camera_connected=CAMERA_STREAM_URL is not None)
    stats = feed.stats
    return LiveFeedOut(
        active=feed.running,
        camera_connected=CAMERA_STREAM_URL is not None,
        source_label=feed.source.label,
        is_demo=feed.source.is_demo,
        started_at=feed.started_at.replace(tzinfo=timezone.utc) if feed.started_at.tzinfo is None else feed.started_at,
        frames_analyzed=feed.frames_analyzed,
        frame_url=f"/incidents/{incident_id}/camera/frame.jpg" if feed.latest_jpeg else None,
        now=LiveStatsOut(**stats.__dict__),
        peak_people=feed.peak_people,
        peak_people_down=feed.peak_people_down,
        peak_people_near_fire=feed.peak_people_near_fire,
        fire_seen=feed.fire_seen,
        snapshots_saved=feed.snapshots_saved,
        error=feed.error,
    )


@router.get("", response_model=LiveFeedOut)
def feed_status(incident_id: int, session: Session = Depends(get_session)):
    _require_incident(session, incident_id)
    return _status(incident_id, live_feeds.get(incident_id))


@router.post("/start", response_model=LiveFeedOut)
def start_feed(incident_id: int, session: Session = Depends(get_session)):
    _require_incident(session, incident_id)
    try:
        feed = live_feeds.start(incident_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=503, detail=str(error))
    return _status(incident_id, feed)


@router.post("/stop", response_model=LiveFeedOut)
def stop_feed(incident_id: int, session: Session = Depends(get_session)):
    _require_incident(session, incident_id)
    return _status(incident_id, live_feeds.stop(incident_id))


@router.get("/frame.jpg")
def latest_frame(incident_id: int):
    feed = live_feeds.get(incident_id)
    if feed is None or feed.latest_jpeg is None:
        raise HTTPException(status_code=404, detail="No camera picture yet")
    # no-store: always fetch the newest picture instead of a cached one
    return Response(content=feed.latest_jpeg, media_type="image/jpeg", headers={"Cache-Control": "no-store"})
