"""
Timeline helpers: called everywhere something worth showing in a history
happens. An incident's timeline shows reports and AI results; a household's
shows profile changes and (later) roll call answers.
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


def add_household_event(
    session: Session,
    household_id: int,
    kind: TimelineKind,
    message: str,
    at: Optional[datetime] = None,
) -> TimelineEvent:
    """Same as add_event, but for a household's history."""
    event = TimelineEvent(household_id=household_id, kind=kind, message=message, created_at=at or utc_now())
    session.add(event)
    return event
