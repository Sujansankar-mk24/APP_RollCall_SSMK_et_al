"""
Database tables.

Each class below is one table in SQLite.

Incident reports (Map and Incidents tabs):
    Incident  1 ──< many  Report   (people reporting the same event)
    Incident  1 ──< many  Media    (photos/videos, each with its AI result)

Roll call (Roll Call tab):
    Household      one home that opted in: where it is, who lives there, and
                   what help they might need in an emergency.
    Volunteer      a neighbor who agreed to check on specific households.
    BuddyLink      which volunteer checks on which household.

Shared:
    TimelineEvent  one history line, for an incident ("AI found fire") or a
                   household ("Profile updated").

All times are stored in UTC and converted to local time only for display.
"""

from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from sqlmodel import Field, SQLModel


def utc_now() -> datetime:
    """Current time in UTC, rounded to whole seconds (keeps JSON dates simple)."""
    return datetime.now(timezone.utc).replace(microsecond=0)


# ---------------------------------------------------------------------------
# Fixed lists of allowed values. Using Enums means a typo like "fier" is
# rejected by the API instead of silently saved.
# ---------------------------------------------------------------------------

class IncidentType(str, Enum):
    # Fire
    fire = "fire"
    smoke = "smoke"
    # Weather
    tornado = "tornado"
    severe_storm = "severe_storm"  # thunderstorm, hail, damaging wind, downed lines
    heavy_rain = "heavy_rain"
    flood = "flood"
    hurricane = "hurricane"        # hurricanes and tropical storms
    winter_storm = "winter_storm"  # ice and snow
    # Medical and other
    injury = "injury"
    other = "other"

    @property
    def label(self) -> str:
        """Human-friendly name, e.g. "Severe storm"."""
        return self.value.replace("_", " ").capitalize()


class IncidentStatus(str, Enum):
    active = "active"          # reported, nobody on the way yet  (red on the map)
    responding = "responding"  # responders are on the way         (amber)
    resolved = "resolved"      # handled                           (gray)


class MediaKind(str, Enum):
    photo = "photo"
    video = "video"


class AnalysisStatus(str, Enum):
    pending = "pending"        # waiting to be analyzed
    processing = "processing"  # AI is working on it right now
    done = "done"
    failed = "failed"


# ---------------------------------------------------------------------------
# Incident reports (Map and Incidents tabs)
# ---------------------------------------------------------------------------

class Incident(SQLModel, table=True):
    """One emergency on the map. Several reports can merge into one incident."""

    id: Optional[int] = Field(default=None, primary_key=True)
    type: IncidentType
    status: IncidentStatus = IncidentStatus.active

    # Where the zone is drawn: the location of the first report.
    latitude: float
    longitude: float
    location_name: str = ""  # e.g. "FM 1570 near Greenville"

    created_at: datetime = Field(default_factory=utc_now)      # first report
    last_report_at: datetime = Field(default_factory=utc_now)  # newest report (used for merging)
    responding_at: Optional[datetime] = None  # when a responder marked it "responding"
    resolved_at: Optional[datetime] = None


class Report(SQLModel, table=True):
    """One resident's report. Belongs to exactly one incident."""

    id: Optional[int] = Field(default=None, primary_key=True)
    incident_id: int = Field(foreign_key="incident.id", index=True)
    description: str = ""
    latitude: float
    longitude: float
    created_at: datetime = Field(default_factory=utc_now)


class Media(SQLModel, table=True):
    """
    A photo or video, plus the AI's findings about it.

    The AI fields start empty (analysis_status = pending) and are filled in by
    the background pipeline in app/ai/pipeline.py.
    """

    id: Optional[int] = Field(default=None, primary_key=True)
    incident_id: int = Field(foreign_key="incident.id", index=True)
    report_id: Optional[int] = Field(default=None, foreign_key="report.id")
    kind: MediaKind

    # Paths are relative to the media folder, e.g. "uploads/3f9c.jpg".
    file_name: str
    thumbnail_name: Optional[str] = None
    annotated_name: Optional[str] = None  # copy with detection boxes drawn on

    created_at: datetime = Field(default_factory=utc_now)

    # ---- AI results ----
    analysis_status: AnalysisStatus = AnalysisStatus.pending
    analyzed_at: Optional[datetime] = None
    analysis_error: Optional[str] = None
    fire_detected: bool = False
    fire_confidence: float = 0.0   # 0.0 to 1.0
    smoke_detected: bool = False
    smoke_confidence: float = 0.0
    people_count: int = 0
    people_down: int = 0           # people who may be lying on the ground (possible injury)
    people_near_fire: int = 0      # people close to the flames
    low_light_used: bool = False   # True if we brightened a dark image before detecting
    brightness: Optional[float] = None  # 0 (black) to 255 (white)
    fire_detector: Optional[str] = None  # which fire detector ran ("basic detector" or a model)
    frames_analyzed: int = 0       # 1 for photos, ~1 per second for videos


# ---------------------------------------------------------------------------
# Roll call (Roll Call tab)
# ---------------------------------------------------------------------------

class Language(str, Enum):
    en = "en"
    es = "es"


class Household(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)

    # Who and where
    contact_name: str                       # e.g. "Margaret Ellis"
    phone: str = ""
    address: str                            # street address
    city: str = ""
    latitude: float
    longitude: float

    # Who lives there
    children: int = 0                       # under 18
    adults: int = 0                         # 18 to 64
    seniors: int = 0                        # 65 and older

    # What help they might need
    mobility_needs: bool = False            # wheelchair, walker, can't use stairs, ...
    medical_equipment: str = ""             # comma-separated, e.g. "oxygen,cpap"
    no_vehicle: bool = False
    pets: bool = False
    livestock: bool = False
    language: Language = Language.en
    notes: str = ""                         # anything else responders should know

    # Who to call
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""

    wants_buddy: bool = False               # asked for a volunteer to check on them
    is_demo: bool = False                   # fictional demo household (never a real person)

    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    # ---- handy facts, worked out from the fields above ----

    @property
    def people(self) -> int:
        return self.children + self.adults + self.seniors

    @property
    def lives_alone(self) -> bool:
        return self.people == 1

    @property
    def equipment_list(self) -> list[str]:
        return [e for e in self.medical_equipment.split(",") if e]


class Volunteer(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    phone: str = ""
    city: str = ""
    latitude: float
    longitude: float
    capacity: int = 5                       # how many households they agreed to check on
    is_demo: bool = False


class BuddyLink(SQLModel, table=True):
    """Volunteer X checks on household Y."""

    id: Optional[int] = Field(default=None, primary_key=True)
    volunteer_id: int = Field(foreign_key="volunteer.id", index=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    created_at: datetime = Field(default_factory=utc_now)


# ---------------------------------------------------------------------------
# Timeline (shared)
# ---------------------------------------------------------------------------

class TimelineKind(str, Enum):
    # Incidents
    report = "report"
    ai_result = "ai_result"
    status_change = "status_change"
    # Households
    profile = "profile"
    buddy = "buddy"


class TimelineEvent(SQLModel, table=True):
    """
    One line of history. It belongs to an incident OR a household, so exactly
    one of incident_id / household_id is set.
    """

    id: Optional[int] = Field(default=None, primary_key=True)
    incident_id: Optional[int] = Field(default=None, foreign_key="incident.id", index=True)
    household_id: Optional[int] = Field(default=None, foreign_key="household.id", index=True)
    kind: TimelineKind
    message: str
    created_at: datetime = Field(default_factory=utc_now)
