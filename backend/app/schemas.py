"""
The JSON shapes the API sends and receives.

These are separate from the database tables (models.py) on purpose: the app
gets exactly the fields it needs, in a friendly form (for example, a ready-made
"Why this priority?" list), and input is checked (lengths, counts, allowed
values) before anything is saved.

The iOS app has matching Swift structs, so if you change a field here, change
it there too.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from app.config import MAX_NOTE_LENGTH, MAX_PEOPLE_PER_HOUSEHOLD, MAX_TEXT_LENGTH, MEDICAL_EQUIPMENT
from app.models import AnalysisStatus, IncidentStatus, IncidentType, Language, MediaKind, TimelineKind

# ---------------------------------------------------------------------------
# Incident reports (Map and Incidents tabs)
# ---------------------------------------------------------------------------

class PriorityFactorOut(BaseModel):
    label: str
    points: int


class PriorityOut(BaseModel):
    score: int   # 0 to 100
    level: str   # "high", "medium" or "low"
    factors: list[PriorityFactorOut]


class AISummaryOut(BaseModel):
    """The AI's findings across ALL of an incident's photos and videos."""

    verified: bool          # the AI saw fire, smoke, or people in at least one
    analyzing: bool         # at least one photo/video is still being analyzed
    fire_detected: bool
    smoke_detected: bool
    people_count: int       # most people seen in a single photo/video
    people_down: int        # most people who may be lying down, in a single photo/video
    people_near_fire: int   # most people close to the flames, in a single photo/video
    low_light_used: bool


class AnalysisOut(BaseModel):
    """The AI's findings for ONE photo or video."""

    status: AnalysisStatus
    fire_detected: bool
    fire_confidence: float
    smoke_detected: bool
    smoke_confidence: float
    people_count: int
    people_down: int
    people_near_fire: int
    low_light_used: bool
    brightness: Optional[float]
    detector: Optional[str]  # which fire detector ran
    frames_analyzed: int
    annotated_url: Optional[str]  # image with detection boxes drawn on
    analyzed_at: Optional[datetime]
    error: Optional[str]


class MediaOut(BaseModel):
    id: int
    report_id: Optional[int]
    kind: MediaKind
    url: str                      # e.g. "/media/uploads/abc.jpg" (add it to the server address)
    thumbnail_url: Optional[str]
    created_at: datetime
    analysis: AnalysisOut


class ReportOut(BaseModel):
    id: int
    description: str
    latitude: float
    longitude: float
    created_at: datetime


class TimelineEventOut(BaseModel):
    id: int
    kind: TimelineKind
    message: str
    created_at: datetime


class IncidentSummaryOut(BaseModel):
    """Everything the map and the incidents list need."""

    id: int
    type: IncidentType
    status: IncidentStatus
    latitude: float
    longitude: float
    location_name: str
    report_count: int
    media_count: int
    first_reported_at: datetime
    last_report_at: datetime
    responding_at: Optional[datetime]
    resolved_at: Optional[datetime]
    priority: PriorityOut
    ai: AISummaryOut
    cover_thumbnail_url: Optional[str]  # a preview picture for list rows


class IncidentDetailOut(IncidentSummaryOut):
    """Everything the detail sheet needs: the summary plus full history."""

    reports: list[ReportOut]
    media: list[MediaOut]
    timeline: list[TimelineEventOut]


class StatusUpdateIn(BaseModel):
    status: IncidentStatus


class ReportCreatedOut(BaseModel):
    incident_id: int
    report_id: int
    media_id: Optional[int]
    merged: bool        # True if the report joined an existing incident
    report_count: int   # how many reports that incident has now
    message: str        # ready to show, e.g. "Added to existing incident (3 reports)"


# ---------------------------------------------------------------------------
# Households (Roll Call tab)
# ---------------------------------------------------------------------------

Text = Field(default="", max_length=MAX_TEXT_LENGTH)
Count = Field(default=0, ge=0, le=MAX_PEOPLE_PER_HOUSEHOLD)


class HouseholdIn(BaseModel):
    """What a resident fills in. Used to create and to update a profile."""

    contact_name: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    phone: str = Text
    address: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    city: str = Text
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)

    children: int = Count
    adults: int = Count
    seniors: int = Count

    mobility_needs: bool = False
    medical_equipment: list[str] = []
    no_vehicle: bool = False
    pets: bool = False
    livestock: bool = False
    language: Language = Language.en
    notes: str = Field(default="", max_length=MAX_NOTE_LENGTH)

    emergency_contact_name: str = Text
    emergency_contact_phone: str = Text
    wants_buddy: bool = False

    @field_validator("medical_equipment")
    @classmethod
    def known_equipment(cls, value: list[str]) -> list[str]:
        unknown = [v for v in value if v not in MEDICAL_EQUIPMENT]
        if unknown:
            raise ValueError(f"Unknown equipment: {', '.join(unknown)}")
        return sorted(set(value))

    @model_validator(mode="after")
    def at_least_one_person(self):
        if self.children + self.adults + self.seniors < 1:
            raise ValueError("A household needs at least one person.")
        return self


class BuddyOut(BaseModel):
    """What a resident sees about their volunteer buddy."""

    id: int
    name: str
    phone: str
    city: str


class HouseholdOut(BaseModel):
    """A household as shown to someone allowed to see it."""

    id: int
    contact_name: str
    phone: str
    address: str
    city: str
    latitude: float
    longitude: float
    children: int
    adults: int
    seniors: int
    people: int
    lives_alone: bool
    mobility_needs: bool
    medical_equipment: list[str]
    no_vehicle: bool
    pets: bool
    livestock: bool
    language: Language
    notes: str
    emergency_contact_name: str
    emergency_contact_phone: str
    wants_buddy: bool
    buddy: Optional[BuddyOut]
    is_demo: bool
    created_at: datetime
    updated_at: datetime


class DemoHousehold(BaseModel):
    id: int
    contact_name: str
    city: str


class DemoVolunteer(BaseModel):
    id: int
    name: str
    city: str
    assigned: int


class DemoIdentities(BaseModel):
    """For the app's role switcher: the fictional people you can act as."""

    households: list[DemoHousehold]
    volunteers: list[DemoVolunteer]
