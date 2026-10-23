"""
Turns database rows into the API's JSON shapes (schemas.py).

Both the incidents and reports endpoints need this, so it lives here once.
"""

from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Session, select

from app.hazards.models import ZoneOut
from app.hazards.zones import HazardKind, report_scale, ring_radii
from app.models import AnalysisStatus, Incident, IncidentStatus, Media, Report, TimelineEvent
from app.schemas import (
    AISummaryOut,
    AnalysisOut,
    IncidentDetailOut,
    IncidentSummaryOut,
    MediaOut,
    PriorityFactorOut,
    PriorityOut,
    ReportOut,
    TimelineEventOut,
)
from app.services.priority import compute_priority, is_verified


def as_utc(moment: Optional[datetime]) -> Optional[datetime]:
    """Make sure a time is labeled as UTC, so the JSON ends in "Z" (SQLite can drop the label)."""
    if moment is None:
        return None
    if moment.tzinfo is None:
        return moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc)


def media_url(name: Optional[str]) -> Optional[str]:
    """"uploads/abc.jpg" -> "/media/uploads/abc.jpg" (the path the server shares files on)."""
    return f"/media/{name}" if name else None


def load_children(session: Session, incident_ids: list[int]) -> tuple[dict, dict]:
    """
    Fetch the reports and media for many incidents in two queries
    (instead of two queries per incident). Returns ({id: reports}, {id: media}).
    """
    reports: dict[int, list[Report]] = {i: [] for i in incident_ids}
    media: dict[int, list[Media]] = {i: [] for i in incident_ids}
    if not incident_ids:
        return reports, media
    for report in session.exec(
        select(Report).where(Report.incident_id.in_(incident_ids)).order_by(Report.created_at)
    ):
        reports[report.incident_id].append(report)
    for item in session.exec(
        select(Media).where(Media.incident_id.in_(incident_ids)).order_by(Media.created_at)
    ):
        media[item.incident_id].append(item)
    return reports, media


def to_summary(incident: Incident, reports: list[Report], media: list[Media]) -> IncidentSummaryOut:
    priority = compute_priority(incident, len(reports), media)
    analyzed = [m for m in media if m.analysis_status == AnalysisStatus.done]

    # Prefer the picture with AI boxes drawn on it as the list preview.
    cover = next((m for m in analyzed if m.fire_detected or m.smoke_detected or m.people_count), None)
    cover = cover or next((m for m in media if m.thumbnail_name), None)

    return IncidentSummaryOut(
        id=incident.id,
        type=incident.type,
        status=incident.status,
        latitude=incident.latitude,
        longitude=incident.longitude,
        location_name=incident.location_name,
        report_count=len(reports),
        media_count=len(media),
        first_reported_at=as_utc(incident.created_at),
        last_report_at=as_utc(incident.last_report_at),
        responding_at=as_utc(incident.responding_at),
        resolved_at=as_utc(incident.resolved_at),
        priority=PriorityOut(
            score=priority.score,
            level=priority.level,
            factors=[PriorityFactorOut(label=f.label, points=f.points) for f in priority.factors],
        ),
        ai=AISummaryOut(
            verified=is_verified(media),
            analyzing=any(m.analysis_status in (AnalysisStatus.pending, AnalysisStatus.processing) for m in media),
            fire_detected=any(m.fire_detected for m in analyzed),
            smoke_detected=any(m.smoke_detected for m in analyzed),
            people_count=max((m.people_count for m in analyzed), default=0),
            people_down=max((m.people_down for m in analyzed), default=0),
            people_near_fire=max((m.people_near_fire for m in analyzed), default=0),
            low_light_used=any(m.low_light_used for m in analyzed),
        ),
        cover_thumbnail_url=media_url(cover.thumbnail_name) if cover else None,
        zones=incident_zones(incident, len(reports)),
    )


def incident_zones(incident: Incident, report_count: int) -> list[ZoneOut]:
    """Three rings around a community report, sized by its type and how many people reported it."""
    if incident.status == IncidentStatus.resolved:
        return []
    radii = ring_radii(HazardKind(incident.type.value), report_scale(report_count))
    return [ZoneOut(level=level, radius_m=radius) for level, radius in radii.items()]


def to_media_out(item: Media) -> MediaOut:
    return MediaOut(
        id=item.id,
        report_id=item.report_id,
        kind=item.kind,
        url=media_url(item.file_name),
        thumbnail_url=media_url(item.thumbnail_name),
        created_at=as_utc(item.created_at),
        analysis=AnalysisOut(
            status=item.analysis_status,
            fire_detected=item.fire_detected,
            fire_confidence=item.fire_confidence,
            smoke_detected=item.smoke_detected,
            smoke_confidence=item.smoke_confidence,
            people_count=item.people_count,
            people_down=item.people_down,
            people_near_fire=item.people_near_fire,
            low_light_used=item.low_light_used,
            brightness=item.brightness,
            detector=item.fire_detector,
            frames_analyzed=item.frames_analyzed,
            annotated_url=media_url(item.annotated_name),
            analyzed_at=as_utc(item.analyzed_at),
            error=item.analysis_error,
        ),
    )


def to_detail(session: Session, incident: Incident) -> IncidentDetailOut:
    reports_by_id, media_by_id = load_children(session, [incident.id])
    reports, media = reports_by_id[incident.id], media_by_id[incident.id]
    timeline = session.exec(
        select(TimelineEvent)
        .where(TimelineEvent.incident_id == incident.id)
        .order_by(TimelineEvent.created_at, TimelineEvent.id)
    ).all()

    summary = to_summary(incident, reports, media)
    return IncidentDetailOut(
        **summary.model_dump(),
        reports=[
            ReportOut(id=r.id, description=r.description, latitude=r.latitude,
                      longitude=r.longitude, created_at=as_utc(r.created_at))
            for r in reports
        ],
        media=[to_media_out(m) for m in media],
        timeline=[
            TimelineEventOut(id=e.id, kind=e.kind, message=e.message, created_at=as_utc(e.created_at))
            for e in timeline
        ],
    )
