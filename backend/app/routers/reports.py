"""
Report endpoint:

  POST /reports   a resident submits a report: what kind of emergency, where,
                  a description (at least 10 characters) and one photo

The request is "multipart/form-data" (the standard way to upload a file
together with text fields). The response comes back immediately; the AI
analysis of the photo/video runs afterwards in the background.
"""

import uuid
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from sqlmodel import Session

from app.ai.pipeline import analyze_media
from app.config import MAX_DESCRIPTION_LENGTH, MAX_UPLOAD_BYTES, MEDIA_DIR, MIN_DESCRIPTION_LENGTH, UPLOADS_DIR
from app.database import get_session
from app.models import IncidentType, MediaKind
from app.schemas import ReportCreatedOut
from app.services.reports import attach_media, count_reports, create_report

router = APIRouter(prefix="/reports", tags=["reports"])

DEFAULT_EXTENSIONS = {MediaKind.photo: ".jpg", MediaKind.video: ".mp4"}
CHUNK_SIZE = 1024 * 1024  # save uploads 1 MB at a time instead of loading them all into memory


def media_kind(upload: UploadFile) -> MediaKind:
    content_type = (upload.content_type or "").lower()
    if content_type.startswith("image/"):
        return MediaKind.photo
    if content_type.startswith("video/"):
        return MediaKind.video
    raise HTTPException(status_code=415, detail="Only photos and videos can be uploaded.")


async def save_upload(upload: UploadFile, kind: MediaKind) -> Path:
    """Save the file under a random name (so two uploads never collide)."""
    extension = Path(upload.filename or "").suffix.lower() or DEFAULT_EXTENSIONS[kind]
    destination = UPLOADS_DIR / f"{uuid.uuid4().hex}{extension}"
    size = 0
    with destination.open("wb") as out:
        while chunk := await upload.read(CHUNK_SIZE):
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                out.close()
                destination.unlink(missing_ok=True)
                raise HTTPException(status_code=413, detail="That file is too large (200 MB max).")
            out.write(chunk)
    if size == 0:
        destination.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="The uploaded file is empty.")
    return destination


@router.post("", response_model=ReportCreatedOut, status_code=201)
async def submit_report(
    background_tasks: BackgroundTasks,
    type: IncidentType = Form(...),
    latitude: float = Form(..., ge=-90, le=90),
    longitude: float = Form(..., ge=-180, le=180),
    description: str = Form("", max_length=MAX_DESCRIPTION_LENGTH),
    location_name: str = Form("", max_length=120),
    scene_labels: str = Form("", max_length=600),   # from the phone's on-device scene check
    file: Optional[UploadFile] = File(None),
    session: Session = Depends(get_session),
):
    # Every report needs a description and a photo of what's happening.
    if len(description.strip()) < MIN_DESCRIPTION_LENGTH:
        raise HTTPException(status_code=422,
                            detail=f"Describe what's happening in at least {MIN_DESCRIPTION_LENGTH} characters.")
    if file is None or not file.filename:
        raise HTTPException(status_code=422, detail="Add a photo of what's happening.")

    # Check and save the file first, so a bad upload doesn't leave a half-made report.
    kind = media_kind(file)
    if kind != MediaKind.photo:
        raise HTTPException(status_code=415, detail="Reports need a photo (not a video).")
    saved_path = await save_upload(file, kind)

    incident, report, merged = create_report(
        session, type, description.strip(), latitude, longitude, location_name.strip()
    )
    # Every brand-new report waits for the AI to see what was reported in
    # the photo before anyone is alerted (see app/ai/verify.py).
    if not merged:
        incident.under_review = True
        session.add(incident)
    media = None
    if saved_path is not None:
        media = attach_media(session, incident, report, saved_path.relative_to(MEDIA_DIR).as_posix(), kind)
        media.scene_labels = scene_labels.strip()[:600]
        session.add(media)
    session.commit()

    # Start the AI after the response is sent, so the app isn't kept waiting.
    if media is not None:
        background_tasks.add_task(analyze_media, media.id)

    total = count_reports(session, incident.id)
    if merged:
        message = f"Added to existing incident ({total} reports)"
    elif incident.under_review:
        message = "Sent. The AI is checking the photo before anyone is alerted"
    else:
        message = "New incident created"
    return ReportCreatedOut(
        incident_id=incident.id,
        report_id=report.id,
        media_id=media.id if media else None,
        merged=merged,
        report_count=total,
        message=message,
    )
