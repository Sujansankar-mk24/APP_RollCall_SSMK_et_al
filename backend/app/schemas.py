"""
The JSON shapes the API sends and receives.

These are separate from the database tables (models.py) on purpose: the app
gets exactly the fields it needs, in a friendly form (for example, a ready-made
"Why this priority?" list), and the database can change without breaking it.

The iOS app has matching Swift structs, so if you change a field here, change
it there too.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from app.models import AnalysisStatus, IncidentStatus, IncidentType, MediaKind, MediaSource, TimelineKind


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
    low_light_used: bool


class AnalysisOut(BaseModel):
    """The AI's findings for ONE photo or video."""

    status: AnalysisStatus
    fire_detected: bool
    fire_confidence: float
    smoke_detected: bool
    smoke_confidence: float
    people_count: int
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
    source: MediaSource
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
