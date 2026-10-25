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

from app.auth import MIN_PASSWORD_LENGTH
from app.hazards.models import ZoneOut
from app.config import (MAX_BIO_LENGTH, MAX_NOTE_LENGTH, MAX_PEOPLE_PER_HOUSEHOLD, MAX_TEXT_LENGTH, MEDICAL_EQUIPMENT,
                        RESPONDER_REPORT_REASONS)
from app.models import (
    AnalysisStatus,
    BuddyStatus,
    IncidentStatus,
    IncidentType,
    Language,
    MediaKind,
    MemberStatus,
    PhotoStatus,
    ResponderStatus,
    TimelineKind,
)

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
    zones: list[ZoneOut] = []           # danger zones on the map (none once resolved)
    under_review: bool = False          # hidden until the AI or a responder confirms it


class IncidentDetailOut(IncidentSummaryOut):
    """Everything the detail sheet needs: the summary plus full history."""

    reports: list[ReportOut]
    media: list[MediaOut]
    timeline: list[TimelineEventOut]


class StatusUpdateIn(BaseModel):
    status: IncidentStatus


class ReviewIn(BaseModel):
    real: bool   # a responder looked: is it a real emergency?


class ReportCreatedOut(BaseModel):
    incident_id: int
    report_id: int
    media_id: Optional[int]
    merged: bool        # True if the report joined an existing incident
    report_count: int   # how many reports that incident has now
    message: str        # ready to show, e.g. "Added to existing incident (3 reports)"


# ---------------------------------------------------------------------------
# Accounts
# ---------------------------------------------------------------------------

Text = Field(default="", max_length=MAX_TEXT_LENGTH)
Count = Field(default=0, ge=0, le=MAX_PEOPLE_PER_HOUSEHOLD)
ZipCode = Field(pattern=r"^\d{5}$")   # a 5-digit US ZIP code

EMAIL_PATTERN = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"


class SignUpIn(BaseModel):
    name: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    email: str = Field(pattern=EMAIL_PATTERN, max_length=MAX_TEXT_LENGTH)
    password: str = Field(min_length=MIN_PASSWORD_LENGTH, max_length=200)

    @field_validator("email")
    @classmethod
    def lowercase(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator("name")
    @classmethod
    def trimmed(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Please enter your name.")
        return value.strip()


class SignInIn(BaseModel):
    email: str
    password: str


class MyCommunityOut(BaseModel):
    id: int
    name: str
    city: str
    status: MemberStatus   # pending (asked to join) or member
    is_admin: bool


class MeOut(BaseModel):
    """Everything the app needs to know about the signed-in person."""

    id: int
    name: str
    email: str
    is_responder: bool
    roll_call_opt_out: bool         # chose "Not now" for the roll call
    household_id: Optional[int]     # their household, if they joined the roll call
    is_volunteer: bool              # agreed to check on neighbors
    community: Optional[MyCommunityOut]
    is_demo: bool
    # Profile
    bio: str
    photo_url: Optional[str]
    phone: str
    away_from_home: bool
    # First responder application: none, pending, approved or rejected
    responder_status: ResponderStatus
    responder_agency: str
    responder_role: str
    responder_city: str


class AuthOut(BaseModel):
    token: str   # the app keeps this in the Keychain and sends it with every request
    me: MeOut


class MePatch(BaseModel):
    roll_call_opt_out: bool


class ProfilePatch(BaseModel):
    """Change any of these (fields left out stay the same)."""

    name: Optional[str] = Field(default=None, min_length=1, max_length=MAX_TEXT_LENGTH)
    bio: Optional[str] = Field(default=None, max_length=MAX_BIO_LENGTH)
    phone: Optional[str] = Field(default=None, max_length=MAX_TEXT_LENGTH)
    away_from_home: Optional[bool] = None


class ResponderInfoOut(BaseModel):
    agency: str
    role: str
    city: str


class PersonOut(BaseModel):
    """
    Someone's profile, as another person sees it. What's included depends on
    who's looking (see app/routers/people.py): the address only for people in
    the same community, the phone only for their buddy.
    """

    id: int
    name: str
    photo_url: Optional[str]
    bio: str
    member_since: datetime
    community_id: Optional[int]
    community_name: Optional[str]
    is_community_admin: bool
    away_from_home: bool
    is_volunteer: bool
    wants_buddy: bool         # joined the roll call and asked for a buddy
    has_buddy: bool
    is_my_buddy: bool         # you check on them, or they check on you
    responder: Optional[ResponderInfoOut]   # only for verified first responders
    address: Optional[str]    # only shown to people in the same community
    phone: Optional[str]      # only shown to their buddy
    # Can you offer to be their volunteer buddy? "none" (not possible),
    # "can_offer", "asked" (waiting for them) or "checking_on" (they accepted).
    buddy_offer: str = "none"
    # Their buddy connections in your community, for the bubble web on their
    # profile: them, who they check on, and who checks on them.
    connections: list["MemberOut"] = []
    connection_pairs: list["BuddyPairOut"] = []


class ResponderReportIn(BaseModel):
    reason: str
    details: str = Field(default="", max_length=MAX_NOTE_LENGTH)

    @field_validator("reason")
    @classmethod
    def known_reason(cls, value: str) -> str:
        if value not in RESPONDER_REPORT_REASONS:
            raise ValueError(f"reason must be one of {RESPONDER_REPORT_REASONS}")
        return value


class VolunteerIn(BaseModel):
    phone: str = Text
    city: str = Text
    capacity: int = Field(default=5, ge=1, le=10)


# ---------------------------------------------------------------------------
# Households (Roll Call tab)
# ---------------------------------------------------------------------------


class HouseholdIn(BaseModel):
    """What a resident fills in. Used to create and to update a profile."""

    contact_name: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    phone: str = Text
    address: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    city: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    zip_code: str = ZipCode
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
    user_id: int              # to open their profile
    name: str
    phone: str
    city: str


class HouseholdOut(BaseModel):
    """A household as shown to someone allowed to see it."""

    id: int
    owner_id: int             # the resident's account, to open their profile
    owner_name: str = ""      # the account's current name (follows profile changes)
    owner_photo_url: Optional[str] = None   # the account's current profile picture
    contact_name: str         # the name typed when the household signed up
    phone: str
    address: str
    city: str
    zip_code: str
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
    check_in: str                       # "safe", "needs_help", or "" (no check-in yet)
    checked_in_at: Optional[datetime]
    buddy: Optional[BuddyOut]
    is_demo: bool
    created_at: datetime
    updated_at: datetime


# ---------------------------------------------------------------------------
# Volunteer buddies
# ---------------------------------------------------------------------------

class BuddyRequestToMe(BaseModel):
    """A volunteer asking to check on the resident's household."""

    id: int
    volunteer_name: str
    volunteer_city: str
    same_community: bool
    created_at: datetime


class BuddyRequestSent(BaseModel):
    """A request a volunteer sent. `label` is what they picked or typed."""

    id: int
    label: str
    status: BuddyStatus
    created_at: datetime


class AddressBuddyIn(BaseModel):
    address: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    city: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    zip_code: str = ZipCode


class CommunityBuddyIn(BaseModel):
    household_id: int


class NeighborWantingBuddy(BaseModel):
    """Only what a neighbor needs to decide to help: first name and street."""

    household_id: int
    first_name: str
    street: str
    city: str
    people: int
    already_asked: bool


# ---------------------------------------------------------------------------
# Communities (Community tab)
# ---------------------------------------------------------------------------

class CommunityIn(BaseModel):
    name: str = Field(min_length=2, max_length=MAX_TEXT_LENGTH)
    city: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)

    @field_validator("name", "city")
    @classmethod
    def trimmed(cls, value: str) -> str:
        return value.strip()


class CommunityOut(BaseModel):
    id: int
    name: str
    city: str
    photo_url: Optional[str]
    member_count: int
    my_status: Optional[MemberStatus]   # None if the viewer hasn't asked to join
    is_admin: bool


class MemberOut(BaseModel):
    user_id: int
    name: str
    is_admin: bool
    since: datetime
    photo_url: Optional[str]
    away_from_home: bool
    has_buddy: bool           # someone checks on them (or they check on someone)
    is_volunteer: bool        # signed up to volunteer (maybe nobody to check on yet)
    checks_on: int            # how many neighbors they actually check on
    wants_buddy: bool         # asked for a buddy and doesn't have one yet


class ReactionOut(BaseModel):
    emoji: str
    count: int
    mine: bool   # did the person looking add this one?


class RecapPhotoOut(BaseModel):
    """One photo in a community's Weekly Recap."""

    id: int
    url: str
    caption: str
    uploader_id: int
    uploader_name: str
    uploader_photo_url: Optional[str]
    reactions: list[ReactionOut] = []
    status: PhotoStatus
    pinned: bool
    created_at: datetime
    expires_at: Optional[datetime]   # None when pinned


class HomeOut(BaseModel):
    """A community member's home on the map (only members of the same community see these)."""

    user_id: int
    name: str
    photo_url: Optional[str]
    latitude: float
    longitude: float
    address: str
    has_buddy: bool
    away_from_home: bool


class BuddyPairOut(BaseModel):
    """Volunteer X checks on resident Y (both in the community)."""

    volunteer_id: int   # user ids
    resident_id: int


class CommunityDetailOut(CommunityOut):
    members: list[MemberOut]            # only shown to members
    buddy_pairs: list[BuddyPairOut]     # who checks on whom (only shown to members)
    join_requests: list[MemberOut]      # only shown to admins
    recap: list[RecapPhotoOut]          # approved photos: anyone can see them
    pending_photos: list[RecapPhotoOut] # only shown to admins


class DeleteAccountIn(BaseModel):
    password: str = Field(max_length=200)


class CheckInIn(BaseModel):
    status: str   # "safe" or "needs_help"

    @field_validator("status")
    @classmethod
    def known_status(cls, value: str) -> str:
        if value not in ("safe", "needs_help"):
            raise ValueError("status must be safe or needs_help")
        return value


class ReactionIn(BaseModel):
    emoji: str


class CommunityPatch(BaseModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=MAX_TEXT_LENGTH)
