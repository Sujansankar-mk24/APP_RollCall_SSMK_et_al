"""
Creating reports. Used by the API (routers/reports.py) and by the demo seed
script, so both follow exactly the same merging rules.
"""

from datetime import datetime
from typing import Optional

from sqlmodel import Session, func, select

from app.models import (
    Incident,
    IncidentType,
    Media,
    MediaKind,
    Report,
    TimelineKind,
    utc_now,
)
from app.services.merging import find_merge_target
from app.services.timeline import add_event


def count_reports(session: Session, incident_id: int) -> int:
    return session.exec(select(func.count()).select_from(Report).where(Report.incident_id == incident_id)).one()


def create_report(
    session: Session,
    incident_type: IncidentType,
    description: str,
    latitude: float,
    longitude: float,
    location_name: str = "",
    at: Optional[datetime] = None,
) -> tuple[Incident, Report, bool]:
    """
    Save a report, either inside a nearby matching incident (merge) or as a
    brand-new incident. Returns (incident, report, merged).
    The caller commits the session.
    """
    now = at or utc_now()
    # If the app couldn't look up a street name, still give people something to read.
    location_name = location_name or f"Near {latitude:.4f}, {longitude:.4f}"
    incident = find_merge_target(session, incident_type, latitude, longitude, now)
    merged = incident is not None

    if incident is None:
        incident = Incident(
            type=incident_type,
            latitude=latitude,
            longitude=longitude,
            location_name=location_name,
            created_at=now,
            last_report_at=now,
        )
        session.add(incident)
        session.flush()  # gives the new incident its id
    else:
        incident.last_report_at = max(incident.last_report_at, now)
        if not incident.location_name and location_name:
            incident.location_name = location_name
        session.add(incident)

    report = Report(
        incident_id=incident.id,
        description=description,
        latitude=latitude,
        longitude=longitude,
        created_at=now,
    )
    session.add(report)
    session.flush()

    quoted = f': "{description}"' if description else ""
    if merged:
        message = f"New report merged into this incident{quoted}"
    else:
        message = f"First report{quoted}"
    add_event(session, incident.id, TimelineKind.report, message, at=now)
    return incident, report, merged


def attach_media(
    session: Session,
    incident: Incident,
    report: Optional[Report],
    file_name: str,
    kind: MediaKind,
    at: Optional[datetime] = None,
) -> Media:
    """
    Record a saved photo/video (file_name is relative to the media folder).
    Its AI analysis starts as "pending"; the pipeline fills it in afterwards.
    """
    media = Media(
        incident_id=incident.id,
        report_id=report.id if report else None,
        kind=kind,
        file_name=file_name,
        created_at=at or utc_now(),
    )
    session.add(media)
    session.flush()
    return media
