"""
Incident endpoints:

  GET   /incidents               list incidents (with optional filters)
  GET   /incidents/{id}          one incident with reports, media, AI results and timeline
  PATCH /incidents/{id}/status   responder marks it responding / resolved
"""

from datetime import timedelta
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select

from app.database import get_session
from app.models import Incident, IncidentStatus, IncidentType, TimelineKind, utc_now
from app.schemas import IncidentDetailOut, IncidentSummaryOut, StatusUpdateIn
from app.services.incident_views import load_children, to_detail, to_summary
from app.services.timeline import add_event

router = APIRouter(prefix="/incidents", tags=["incidents"])

STATUS_MESSAGES = {
    IncidentStatus.active: "Marked active again",
    IncidentStatus.responding: "Responders marked this incident as responding",
    IncidentStatus.resolved: "Responders marked this incident as resolved",
}


@router.get("", response_model=list[IncidentSummaryOut])
def list_incidents(
    type: Optional[list[IncidentType]] = Query(None, description="Only these types (repeat for several)"),
    status: Optional[list[IncidentStatus]] = Query(None, description="Only these statuses (repeat for several)"),
    since_hours: Optional[int] = Query(None, ge=1, description="Only incidents with a report in the last N hours"),
    sort: Literal["priority", "recent"] = "priority",
    session: Session = Depends(get_session),
):
    query = select(Incident)
    if type:
        query = query.where(Incident.type.in_(type))
    if status:
        query = query.where(Incident.status.in_(status))
    if since_hours:
        query = query.where(Incident.last_report_at >= utc_now() - timedelta(hours=since_hours))
    incidents = session.exec(query).all()

    reports, media = load_children(session, [i.id for i in incidents])
    summaries = [to_summary(i, reports[i.id], media[i.id]) for i in incidents]

    if sort == "recent":
        summaries.sort(key=lambda s: s.last_report_at, reverse=True)
    else:
        # Open incidents first, highest score first; ties go to the newest report.
        summaries.sort(key=lambda s: (s.status == IncidentStatus.resolved, -s.priority.score,
                                      -s.last_report_at.timestamp()))
    return summaries


def get_incident_or_404(session: Session, incident_id: int) -> Incident:
    incident = session.get(Incident, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="Incident not found")
    return incident


@router.get("/{incident_id}", response_model=IncidentDetailOut)
def get_incident(incident_id: int, session: Session = Depends(get_session)):
    return to_detail(session, get_incident_or_404(session, incident_id))


@router.patch("/{incident_id}/status", response_model=IncidentDetailOut)
def update_status(incident_id: int, update: StatusUpdateIn, session: Session = Depends(get_session)):
    incident = get_incident_or_404(session, incident_id)
    if incident.status != update.status:
        now = utc_now()
        incident.status = update.status
        # Remember the first time each step happened (used for "average time to response").
        if update.status == IncidentStatus.responding and incident.responding_at is None:
            incident.responding_at = now
        if update.status == IncidentStatus.resolved and incident.resolved_at is None:
            incident.resolved_at = now
        session.add(incident)
        add_event(session, incident.id, TimelineKind.status_change, STATUS_MESSAGES[update.status], at=now)
        session.commit()
        session.refresh(incident)
    return to_detail(session, incident)
