"""Tests for priority scoring (app/services/priority.py)."""

from datetime import datetime, timezone

from app.models import AnalysisStatus, Incident, IncidentType, Media, MediaKind
from app.services.priority import compute_priority, is_night

# 3 PM Central Time (20:00 UTC in October) = daytime, so no night bonus.
AFTERNOON = datetime(2026, 10, 9, 20, 0, tzinfo=timezone.utc)
# 11 PM Central Time = night.
NIGHT = datetime(2026, 10, 10, 4, 0, tzinfo=timezone.utc)


def make_incident(type=IncidentType.fire, created_at=AFTERNOON):
    return Incident(id=1, type=type, latitude=33.0, longitude=-96.0, created_at=created_at, last_report_at=created_at)


def analyzed(fire=False, smoke=False, people=0, low_light=False, down=0, near_fire=0):
    return Media(id=1, incident_id=1, kind=MediaKind.photo, file_name="x.jpg",
                 analysis_status=AnalysisStatus.done, fire_detected=fire, smoke_detected=smoke,
                 people_count=people, low_light_used=low_light, people_down=down, people_near_fire=near_fire)


def labels(result):
    return {f.label: f.points for f in result.factors}


def test_unverified_report_with_no_media_scores_low():
    result = compute_priority(make_incident(), report_count=1, media=[])
    assert labels(result) == {"Fire report": 20, "Not yet verified by AI": -20}
    assert result.score == 0 and result.level == "low"


def test_confirmed_fire_with_people_is_high():
    result = compute_priority(make_incident(), report_count=1, media=[analyzed(fire=True, people=2)])
    assert labels(result) == {"Fire report": 20, "Fire confirmed by AI": 40, "2 people detected by AI": 30}
    assert result.score == 90 and result.level == "high"


def test_people_points_are_capped():
    result = compute_priority(make_incident(IncidentType.injury), report_count=1, media=[analyzed(people=10)])
    assert labels(result)["10 people detected by AI"] == 45


def test_extra_reports_add_points_and_are_capped():
    assert labels(compute_priority(make_incident(), 3, []))["2 more reports from the area"] == 10
    assert labels(compute_priority(make_incident(), 20, []))["19 more reports from the area"] == 25


def test_night_or_low_light_adds_points():
    assert "Low light / night" in labels(compute_priority(make_incident(created_at=NIGHT), 1, []))
    assert "Low light / night" in labels(compute_priority(make_incident(), 1, [analyzed(people=1, low_light=True)]))


def test_media_still_being_analyzed_does_not_count_yet():
    pending = Media(id=1, incident_id=1, kind=MediaKind.photo, file_name="x.jpg", fire_detected=True)
    assert "Fire confirmed by AI" not in labels(compute_priority(make_incident(), 1, [pending]))


def test_score_stays_between_0_and_100():
    everything = [analyzed(fire=True, smoke=True, people=5, low_light=True)]
    assert compute_priority(make_incident(created_at=NIGHT), 10, everything).score == 100
    assert compute_priority(make_incident(IncidentType.smoke), 1, []).score == 0


def test_weather_reports_are_not_marked_down_for_missing_ai_evidence():
    # The AI can't recognize a tornado, so there is no "Not yet verified" penalty.
    result = compute_priority(make_incident(IncidentType.tornado), report_count=3, media=[])
    assert labels(result) == {"Tornado report": 40, "2 more reports from the area": 10}
    assert result.score == 50 and result.level == "medium"


def test_multi_word_type_labels():
    assert "Severe storm report" in labels(compute_priority(make_incident(IncidentType.severe_storm), 1, []))


def test_people_who_may_need_help_add_points():
    result = labels(compute_priority(make_incident(), 1, [analyzed(fire=True, people=2, down=1, near_fire=1)]))
    assert result["Someone may be down (lying on the ground)"] == 15
    assert result["People close to the flames"] == 10


def test_is_night_uses_central_time():
    assert is_night(NIGHT)
    assert not is_night(AFTERNOON)
