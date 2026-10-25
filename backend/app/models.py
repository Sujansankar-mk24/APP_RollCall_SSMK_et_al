"""
Database tables.

Each class below is one table in SQLite.

Incident reports (Map and Incidents tabs):
    Incident  1 ──< many  Report   (people reporting the same event)
    Incident  1 ──< many  Media    (photos/videos, each with its AI result)

Accounts:
    User              one person's account (email + hashed password).
    AuthToken         a "remember me" sign-in token for one device.

Roll call (Roll Call tab):
    Household         one home that opted in, owned by one User: where it is,
                      who lives there, and what help they might need.
    Volunteer         a User who agreed to check on neighbors.
    BuddyLink         a volunteer checking on a household. It starts as a
                      request, and the resident must accept it.

Communities (Community tab):
    Community         a neighborhood, e.g. "Pecan Hollow" in Greenville.
    CommunityMember   a User in a community (or asking to join one).

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
    # A new fire, smoke or injury report starts out "under review": it isn't
    # on the map and nobody is warned until the AI finds what was reported in
    # the photo (or a verified responder confirms it).
    under_review: bool = False


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
    # What the phone's on-device scene check (Apple Vision) saw, e.g.
    # "snow:0.82,blizzard:0.41". See app/ai/verify.py.
    scene_labels: str = ""


# ---------------------------------------------------------------------------
# Accounts
# ---------------------------------------------------------------------------

class ResponderStatus(str, Enum):
    none = "none"          # a regular account
    pending = "pending"    # applied as a first responder; waiting for review
    approved = "approved"  # verified: can mark incidents responding or resolved
    rejected = "rejected"  # the application was turned down


class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    email: str = Field(index=True, unique=True)   # always stored in lowercase
    password_hash: str                            # never the password itself (see app/auth.py)
    is_responder: bool = False                    # a verified first responder (see responder_status)
    roll_call_opt_out: bool = False               # chose "Not now" for the roll call
    is_demo: bool = False                         # fictional demo account
    created_at: datetime = Field(default_factory=utc_now)

    # Profile (what others see when they open your profile)
    bio: str = ""                                 # a short introduction, like an Instagram bio
    photo_path: Optional[str] = None              # under media/, e.g. "profiles/ab12.jpg"
    phone: str = ""                               # shown only to your buddy
    away_from_home: bool = False                  # "Away from home" next to your name in your community

    # First responder application. The ID photo is kept in private/ (never
    # served to anyone) and deleted as soon as it's reviewed.
    responder_status: ResponderStatus = ResponderStatus.none
    responder_agency: str = ""                    # e.g. "Greenville Fire-Rescue"
    responder_role: str = ""                      # e.g. "Firefighter"
    responder_badge: str = ""                     # badge or employee number
    responder_city: str = ""                      # the area they serve
    responder_id_photo: Optional[str] = None      # path under private/, until reviewed
    responder_check: str = ""                     # the automatic check, as JSON (app/services/responder_check.py)


class ResponderReport(SQLModel, table=True):
    """A resident flags a first responder (fake, abusing the role, reckless)."""

    id: Optional[int] = Field(default=None, primary_key=True)
    responder_id: int = Field(foreign_key="user.id", index=True)
    reporter_id: int = Field(foreign_key="user.id")
    reason: str                                   # see RESPONDER_REPORT_REASONS
    details: str = ""
    reviewed: bool = False
    created_at: datetime = Field(default_factory=utc_now)


class AuthToken(SQLModel, table=True):
    """Keeps a device signed in. Only a hash of the token is stored."""

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    token_hash: str = Field(index=True, unique=True)
    created_at: datetime = Field(default_factory=utc_now)


# ---------------------------------------------------------------------------
# Roll call (Roll Call tab)
# ---------------------------------------------------------------------------

class Language(str, Enum):
    en = "en"
    es = "es"


class Household(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="user.id", index=True, unique=True)   # one household per account

    # Who and where
    contact_name: str                       # e.g. "Margaret Ellis"
    phone: str = ""
    address: str                            # street address, typed by the resident
    city: str = ""
    zip_code: str = ""
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

    # The latest check-in: "safe" or "needs_help" (from the app, a
    # notification button, or the Lock Screen), and when.
    check_in: str = ""
    checked_in_at: Optional[datetime] = None
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
    """A user who agreed to check on neighbors during an emergency."""

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True, unique=True)
    phone: str = ""
    city: str = ""
    capacity: int = 5                       # how many households they agreed to check on
    created_at: datetime = Field(default_factory=utc_now)


class BuddyStatus(str, Enum):
    pending = "pending"    # asked; waiting for the resident to accept
    active = "active"      # the resident accepted
    declined = "declined"  # the resident said no


class BuddyLink(SQLModel, table=True):
    """
    Volunteer X checks on household Y.

    A volunteer either picks a neighbor from their community's list, or types
    an address. A typed address that matches no household (or one that doesn't
    accept outside buddies) is still saved, with household_id left empty, so
    the volunteer can never use this to find out who lives where.
    """

    id: Optional[int] = Field(default=None, primary_key=True)
    volunteer_id: int = Field(foreign_key="volunteer.id", index=True)
    household_id: Optional[int] = Field(default=None, foreign_key="household.id", index=True)
    typed_address: str = ""                 # what the volunteer typed, if they used an address
    status: BuddyStatus = BuddyStatus.pending
    created_at: datetime = Field(default_factory=utc_now)
    answered_at: Optional[datetime] = None


# ---------------------------------------------------------------------------
# Communities (Community tab)
# ---------------------------------------------------------------------------

class Community(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str                               # e.g. "Pecan Hollow"
    city: str
    allow_outside_buddies: bool = False     # no longer used: buddies come from the same community
    created_by: int = Field(foreign_key="user.id")
    photo_path: Optional[str] = None        # the community's picture, under media/
    is_demo: bool = False
    created_at: datetime = Field(default_factory=utc_now)


class MemberStatus(str, Enum):
    pending = "pending"    # asked to join; an admin hasn't answered yet
    member = "member"


class CommunityMember(SQLModel, table=True):
    """A user in a community. Each user belongs to (or is asking to join) at most one."""

    id: Optional[int] = Field(default=None, primary_key=True)
    community_id: int = Field(foreign_key="community.id", index=True)
    user_id: int = Field(foreign_key="user.id", index=True, unique=True)
    status: MemberStatus = MemberStatus.pending
    is_admin: bool = False
    created_at: datetime = Field(default_factory=utc_now)


class PhotoStatus(str, Enum):
    pending = "pending"    # waiting for the admin
    approved = "approved"  # in the Weekly Recap
    rejected = "rejected"


class CommunityPhoto(SQLModel, table=True):
    """
    A photo for the community's Weekly Recap. The admin approves it first.
    Approved photos show for 7 days, unless the admin pins them so they stay.
    """

    id: Optional[int] = Field(default=None, primary_key=True)
    community_id: int = Field(foreign_key="community.id", index=True)
    uploader_id: int = Field(foreign_key="user.id")
    path: str                               # under media/
    caption: str = ""
    status: PhotoStatus = PhotoStatus.pending
    pinned: bool = False
    created_at: datetime = Field(default_factory=utc_now)
    approved_at: Optional[datetime] = None


class RecapReaction(SQLModel, table=True):
    """An emoji sticker someone put on a Weekly Recap photo (one per person per photo)."""

    id: Optional[int] = Field(default=None, primary_key=True)
    photo_id: int = Field(foreign_key="communityphoto.id", index=True)
    user_id: int = Field(foreign_key="user.id")
    emoji: str
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
    community = "community"
    check_in = "check_in"


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
