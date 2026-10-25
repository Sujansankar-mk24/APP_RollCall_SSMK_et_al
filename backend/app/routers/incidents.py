"""
Incident endpoints:

  GET   /incidents               list incidents (with optional filters)
  GET   /incidents/{id}          one incident with reports, media, AI results and timeline
  PATCH /incidents/{id}/status   a verified first responder marks it responding / resolved
                                 (not for tornadoes, hurricanes and other weather nobody can stop)
  POST  /incidents/{id}/review   a verified first responder confirms (or dismisses) a report
                                 the AI couldn't confirm

Reports under review (the AI hasn't found what was reported yet) aren't in
the list, so they're not on the map and nobody is warned. Verified first
responders see them, marked as under review, so they can check them.
"""

from datetime import timedelta
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select

from app.auth import current_user, optional_user
from app.config import NATURAL_HAZARD_TYPES
from app.database import get_session
from app.models import Incident, IncidentStatus, IncidentType, TimelineKind, User, utc_now
from app.schemas import IncidentDetailOut, IncidentSummaryOut, ReviewIn, StatusUpdateIn
from app.services.incident_views import load_children, to_detail, to_summary
from app.services.people import is_verified_responder
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
    user: Optional[User] = Depends(optional_user),
    session: Session = Depends(get_session),
):
    query = select(Incident)
    if user is None or not is_verified_responder(user):
        query = query.where(Incident.under_review == False)  # noqa: E712 (SQL needs ==)
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
def update_status(incident_id: int, update: StatusUpdateIn, user: User = Depends(current_user),
                  session: Session = Depends(get_session)):
    if not is_verified_responder(user):
        raise HTTPException(status_code=403,
                            detail="Only verified first responders can mark an incident responding or resolved.")
    incident = get_incident_or_404(session, incident_id)
    if incident.type.value in NATURAL_HAZARD_TYPES:
        raise HTTPException(status_code=400,
                            detail="Nobody can stop this kind of hazard, so it ends on its own when the weather passes.")
    if incident.status != update.status:
        now = utc_now()
        incident.status = update.status
        # Remember the first time each step happened (used for "average time to response").
        if update.status == IncidentStatus.responding and incident.responding_at is None:
            incident.responding_at = now
        if update.status == IncidentStatus.resolved and incident.resolved_at is None:
            incident.resolved_at = now
        session.add(incident)
        who = f" ({user.responder_agency})" if user.responder_agency else ""
        add_event(session, incident.id, TimelineKind.status_change, STATUS_MESSAGES[update.status] + who, at=now)
        session.commit()
        session.refresh(incident)
    return to_detail(session, incident)


@router.post("/{incident_id}/review", response_model=IncidentDetailOut)
def review(incident_id: int, data: ReviewIn, user: User = Depends(current_user),
           session: Session = Depends(get_session)):
    """A verified first responder looked at a report the AI couldn't confirm."""
    if not is_verified_responder(user):
        raise HTTPException(status_code=403, detail="Only verified first responders can review reports.")
    incident = get_incident_or_404(session, incident_id)
    who = f" ({user.responder_agency})" if user.responder_agency else ""
    now = utc_now()
    if data.real:
        incident.under_review = False
        add_event(session, incident.id, TimelineKind.status_change, f"Confirmed as real by a responder{who}. Now on the map.", at=now)
    else:
        # Not a real emergency: closed, and it stays off the map.
        incident.status = IncidentStatus.resolved
        incident.resolved_at = incident.resolved_at or now
        add_event(session, incident.id, TimelineKind.status_change, f"Dismissed by a responder{who}: not an emergency.", at=now)
    session.add(incident)
    session.commit()
    session.refresh(incident)
    return to_detail(session, incident)
