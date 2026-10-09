"""
Timeline helper: one function used everywhere something worth showing happens.
"""

from datetime import datetime
from typing import Optional

from sqlmodel import Session

from app.models import TimelineEvent, TimelineKind, utc_now


def add_event(
    session: Session,
    incident_id: int,
    kind: TimelineKind,
    message: str,
    at: Optional[datetime] = None,
) -> TimelineEvent:
    """
    Record an event in an incident's history. The caller commits the session.
    `at` is only passed by the demo seed script to backdate events.
    """
    event = TimelineEvent(incident_id=incident_id, kind=kind, message=message, created_at=at or utc_now())
    session.add(event)
    return event
