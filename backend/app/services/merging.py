"""
Report merging.

When several people report the same grass fire, responders should see ONE
incident with several reports, not several separate dots on the map.

Rule: a new report is added to an existing incident when ALL of these are true:
  1. same incident type (a flood report never merges into a fire),
  2. the incident is still open (not resolved),
  3. the incident's newest report was within the last MERGE_WINDOW_HOURS,
  4. the new report is within MERGE_RADIUS_METERS of the incident.
If several incidents qualify, the closest one wins.
"""

import math
from datetime import datetime, timedelta
from typing import Optional, Sequence

from sqlmodel import Session, select

from app.config import MERGE_RADIUS_METERS, MERGE_WINDOW_HOURS
from app.models import Incident, IncidentStatus, IncidentType

EARTH_RADIUS_METERS = 6_371_000


def distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Distance between two GPS points along the Earth's surface
    (the "haversine formula"). Accurate to well under a meter at these distances.
    """
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * EARTH_RADIUS_METERS * math.asin(math.sqrt(a))


def pick_merge_target(
    candidates: Sequence[Incident],
    incident_type: IncidentType,
    latitude: float,
    longitude: float,
    now: datetime,
) -> Optional[Incident]:
    """
    Pure decision function: given some incidents, return the one this report
    should merge into, or None to start a new incident. (No database access,
    which makes it easy to unit-test.)
    """
    window_start = now - timedelta(hours=MERGE_WINDOW_HOURS)
    best: Optional[Incident] = None
    best_distance = float("inf")

    for incident in candidates:
        if incident.type != incident_type:
            continue
        if incident.status == IncidentStatus.resolved:
            continue
        if incident.last_report_at < window_start:
            continue
        distance = distance_meters(latitude, longitude, incident.latitude, incident.longitude)
        if distance <= MERGE_RADIUS_METERS and distance < best_distance:
            best, best_distance = incident, distance

    return best


def find_merge_target(
    session: Session,
    incident_type: IncidentType,
    latitude: float,
    longitude: float,
    now: datetime,
) -> Optional[Incident]:
    """Load the possible matches from the database, then apply the rule above."""
    window_start = now - timedelta(hours=MERGE_WINDOW_HOURS)
    candidates = session.exec(
        select(Incident).where(
            Incident.type == incident_type,
            Incident.status != IncidentStatus.resolved,
            Incident.last_report_at >= window_start,
        )
    ).all()
    return pick_merge_target(candidates, incident_type, latitude, longitude, now)
