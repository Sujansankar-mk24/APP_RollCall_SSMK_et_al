"""
The JSON shapes the API sends and receives.

These are separate from the database tables (models.py) on purpose: the app
gets exactly the fields it needs in a friendly form, and input is checked
(lengths, counts, allowed values) before anything is saved.

The iOS app has matching Swift structs, so if you change a field here, change
it there too.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from app.config import MAX_NOTE_LENGTH, MAX_PEOPLE_PER_HOUSEHOLD, MAX_TEXT_LENGTH, MEDICAL_EQUIPMENT
from app.models import Language

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
