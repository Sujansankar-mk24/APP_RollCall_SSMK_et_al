"""
Database tables.

Each class below is one table in SQLite:

    Household      one home that opted in: where it is, who lives there, and
                   what help they might need in an emergency.
    Volunteer      a neighbor who agreed to check on specific households.
    BuddyLink      which volunteer checks on which household.
    TimelineEvent  a history line ("Profile updated", later "Roll call sent", ...).

More tables (emergency events, check-ins) are added in later steps.
All times are stored in UTC and converted to local time only for display.
"""

from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from sqlmodel import Field, SQLModel


def utc_now() -> datetime:
    """Current time in UTC, rounded to whole seconds (keeps JSON dates simple)."""
    return datetime.now(timezone.utc).replace(microsecond=0)


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


class TimelineKind(str, Enum):
    profile = "profile"
    buddy = "buddy"


class TimelineEvent(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: Optional[int] = Field(default=None, index=True)
    kind: TimelineKind
    message: str
    created_at: datetime = Field(default_factory=utc_now)
