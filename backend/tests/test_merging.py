"""Tests for the report-merging rule (app/services/merging.py)."""

from datetime import datetime, timedelta, timezone

from app.models import Incident, IncidentStatus, IncidentType
from app.services.merging import distance_meters, pick_merge_target

NOW = datetime(2026, 10, 9, 18, 0, tzinfo=timezone.utc)
GREENVILLE = (33.0705, -96.1050)


def incident(type=IncidentType.fire, status=IncidentStatus.active, minutes_ago=30, north_m=0.0, id=1):
    latitude = GREENVILLE[0] + north_m / 111_320  # move north by north_m meters
    return Incident(id=id, type=type, status=status, latitude=latitude, longitude=GREENVILLE[1],
                    last_report_at=NOW - timedelta(minutes=minutes_ago))


def test_distance_is_accurate():
    # 0.01 degrees of latitude is about 1,113 meters.
    assert abs(distance_meters(33.0, -96.0, 33.01, -96.0) - 1113) < 2


def test_merges_nearby_recent_same_type():
    target = incident(north_m=200)
    assert pick_merge_target([target], IncidentType.fire, *GREENVILLE, NOW) is target


def test_does_not_merge_when_too_far():
    assert pick_merge_target([incident(north_m=350)], IncidentType.fire, *GREENVILLE, NOW) is None


def test_does_not_merge_different_type():
    assert pick_merge_target([incident(type=IncidentType.flood)], IncidentType.fire, *GREENVILLE, NOW) is None


def test_does_not_merge_into_resolved_incident():
    resolved = incident(status=IncidentStatus.resolved)
    assert pick_merge_target([resolved], IncidentType.fire, *GREENVILLE, NOW) is None


def test_does_not_merge_when_too_old():
    assert pick_merge_target([incident(minutes_ago=121)], IncidentType.fire, *GREENVILLE, NOW) is None


def test_merges_into_responding_incident():
    responding = incident(status=IncidentStatus.responding)
    assert pick_merge_target([responding], IncidentType.fire, *GREENVILLE, NOW) is responding


def test_picks_the_closest_match():
    far, near = incident(north_m=250, id=1), incident(north_m=50, id=2)
    assert pick_merge_target([far, near], IncidentType.fire, *GREENVILLE, NOW) is near
