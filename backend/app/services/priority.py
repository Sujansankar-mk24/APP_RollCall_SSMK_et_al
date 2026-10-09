"""
Priority scoring.

Responders need to know which incident to go to first. Instead of a "black box"
machine-learning model, RescueSight adds up simple rules that anyone can check.
Every rule that applies becomes one line in the app's "Why this priority?" list.

Rules (points):
  Starting points by type .... tornado +40, hurricane +40, fire +20, injury +20,
                               flood +20, severe storm +20, winter storm +20,
                               heavy rain +10, smoke +10, other +5
  Fire confirmed by AI ....... +40
  Smoke confirmed by AI ...... +20
  People seen by AI .......... +15 each, up to +45 (3 people)
  Extra reports .............. +5 each, up to +25
  Low light / night .......... +5
  Not verified by AI ......... -20   (fire, smoke and injury reports only: no photo/video
                                      shows fire, smoke, or people yet)

Why is the -20 only for fire, smoke and injury? The AI can look for flames,
smoke and people, so for those reports "no evidence yet" means something. It
cannot recognize a tornado, a flood or ice on a road, so weather reports are
not marked down just because the AI can't confirm them; the number of
independent reports counts instead.

The total is kept between 0 and 100.
  60+ = high, 30-59 = medium, under 30 = low.
"""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Sequence
from zoneinfo import ZoneInfo

from app.config import LOCAL_TIMEZONE
from app.models import AnalysisStatus, Incident, IncidentType, Media

TYPE_BASE_POINTS = {
    IncidentType.tornado: 40,
    IncidentType.hurricane: 40,
    IncidentType.fire: 20,
    IncidentType.injury: 20,
    IncidentType.flood: 20,
    IncidentType.severe_storm: 20,
    IncidentType.winter_storm: 20,
    IncidentType.heavy_rain: 10,
    IncidentType.smoke: 10,
    IncidentType.other: 5,
}

# Types the AI can actually confirm from a photo (flames, smoke, or people).
AI_VERIFIABLE_TYPES = {IncidentType.fire, IncidentType.smoke, IncidentType.injury}
FIRE_POINTS = 40
SMOKE_POINTS = 20
POINTS_PER_PERSON = 15
MAX_PEOPLE_POINTS = 45
POINTS_PER_EXTRA_REPORT = 5
MAX_EXTRA_REPORT_POINTS = 25
LOW_LIGHT_POINTS = 5
UNVERIFIED_POINTS = -20

HIGH_THRESHOLD = 60
MEDIUM_THRESHOLD = 30

# Night = 8 PM to 6 AM local time.
NIGHT_START_HOUR = 20
NIGHT_END_HOUR = 6


@dataclass
class PriorityFactor:
    label: str   # e.g. "Fire confirmed by AI"
    points: int  # e.g. 40


@dataclass
class PriorityResult:
    score: int
    level: str  # "high", "medium" or "low"
    factors: list[PriorityFactor] = field(default_factory=list)


def is_night(moment_utc: datetime) -> bool:
    """True if this UTC time is between 8 PM and 6 AM in North Texas."""
    if moment_utc.tzinfo is None:  # treat a time without a zone as UTC
        moment_utc = moment_utc.replace(tzinfo=timezone.utc)
    local = moment_utc.astimezone(ZoneInfo(LOCAL_TIMEZONE))
    return local.hour >= NIGHT_START_HOUR or local.hour < NIGHT_END_HOUR


def is_verified(media: Sequence[Media]) -> bool:
    """An incident is verified once the AI finds fire, smoke, or a person in any of its media."""
    return any(
        m.analysis_status == AnalysisStatus.done
        and (m.fire_detected or m.smoke_detected or m.people_count > 0)
        for m in media
    )


def compute_priority(incident: Incident, report_count: int, media: Sequence[Media]) -> PriorityResult:
    """Add up every rule that applies to this incident."""
    analyzed = [m for m in media if m.analysis_status == AnalysisStatus.done]
    factors: list[PriorityFactor] = []

    # 1. Some emergencies are more dangerous to begin with.
    factors.append(PriorityFactor(f"{incident.type.label} report", TYPE_BASE_POINTS[incident.type]))

    # 2. What the AI actually saw in the photos/videos.
    if any(m.fire_detected for m in analyzed):
        factors.append(PriorityFactor("Fire confirmed by AI", FIRE_POINTS))
    if any(m.smoke_detected for m in analyzed):
        factors.append(PriorityFactor("Smoke confirmed by AI", SMOKE_POINTS))

    # Use the single photo/video with the most people (not the sum), because
    # several photos of one scene usually show the same people.
    most_people = max((m.people_count for m in analyzed), default=0)
    if most_people > 0:
        points = min(most_people * POINTS_PER_PERSON, MAX_PEOPLE_POINTS)
        noun = "person" if most_people == 1 else "people"
        factors.append(PriorityFactor(f"{most_people} {noun} detected by AI", points))

    # 3. More independent reports = more likely real and probably bigger.
    extra_reports = max(report_count - 1, 0)
    if extra_reports > 0:
        points = min(extra_reports * POINTS_PER_EXTRA_REPORT, MAX_EXTRA_REPORT_POINTS)
        noun = "report" if extra_reports == 1 else "reports"
        factors.append(PriorityFactor(f"{extra_reports} more {noun} from the area", points))

    # 4. Darkness makes a scene harder and more dangerous to reach.
    if any(m.low_light_used for m in analyzed) or is_night(incident.created_at):
        factors.append(PriorityFactor("Low light / night", LOW_LIGHT_POINTS))

    # 5. No visual evidence yet for a type the AI can check: could be a false
    #    alarm, so rank it lower.
    if incident.type in AI_VERIFIABLE_TYPES and not is_verified(media):
        factors.append(PriorityFactor("Not yet verified by AI", UNVERIFIED_POINTS))

    total = sum(f.points for f in factors)
    score = max(0, min(100, total))

    if score >= HIGH_THRESHOLD:
        level = "high"
    elif score >= MEDIUM_THRESHOLD:
        level = "medium"
    else:
        level = "low"

    return PriorityResult(score=score, level=level, factors=factors)
