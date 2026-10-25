"""
Turning a Household row into what the API sends, plus deleting a household
and everything attached to it.
"""

from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Session, delete, select

from app.models import BuddyLink, BuddyStatus, Household, TimelineEvent, User, Volunteer
from app.schemas import BuddyOut, HouseholdIn, HouseholdOut
from app.services.incident_views import media_url


def utc(moment: datetime) -> datetime:
    """SQLite forgets time zones; every time we store is UTC, so say so."""
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def buddies_of(session: Session, household_id: int) -> list[BuddyOut]:
    """Every volunteer the household accepted (a household can have several)."""
    links = session.exec(select(BuddyLink).where(
        BuddyLink.household_id == household_id, BuddyLink.status == BuddyStatus.active)
        .order_by(BuddyLink.answered_at)).all()
    out = []
    for link in links:
        volunteer = session.get(Volunteer, link.volunteer_id)
        user = session.get(User, volunteer.user_id) if volunteer else None
        if user is not None:
            out.append(BuddyOut(id=volunteer.id, user_id=user.id, name=user.name,
                                phone=volunteer.phone or user.phone, city=volunteer.city))
    return out


def to_out(session: Session, household: Household) -> HouseholdOut:
    # The account's name and picture right now, so a renamed neighbor shows
    # their new name everywhere (contact_name is only what they typed at sign-up).
    owner = session.get(User, household.owner_id)
    buddies = buddies_of(session, household.id)
    return HouseholdOut(
        id=household.id,
        owner_id=household.owner_id,
        owner_name=owner.name if owner else household.contact_name,
        owner_photo_url=media_url(owner.photo_path) if owner else None,
        contact_name=household.contact_name,
        phone=household.phone,
        address=household.address,
        city=household.city,
        zip_code=household.zip_code,
        latitude=household.latitude,
        longitude=household.longitude,
        children=household.children,
        adults=household.adults,
        seniors=household.seniors,
        people=household.people,
        lives_alone=household.lives_alone,
        mobility_needs=household.mobility_needs,
        medical_equipment=household.equipment_list,
        no_vehicle=household.no_vehicle,
        pets=household.pets,
        livestock=household.livestock,
        language=household.language,
        notes=household.notes,
        emergency_contact_name=household.emergency_contact_name,
        emergency_contact_phone=household.emergency_contact_phone,
        wants_buddy=household.wants_buddy,
        check_in=household.check_in,
        checked_in_at=utc(household.checked_in_at) if household.checked_in_at else None,
        buddy=buddies[0] if buddies else None,
        buddies=buddies,
        is_demo=household.is_demo,
        created_at=utc(household.created_at),
        updated_at=utc(household.updated_at),
    )


def apply(household: Household, data: HouseholdIn) -> None:
    """Copy what the resident filled in onto the database row."""
    for field, value in data.model_dump().items():
        if field == "medical_equipment":
            value = ",".join(value)
        setattr(household, field, value)


def delete_everything(session: Session, household: Household) -> None:
    """'Delete my data': remove the household and every row that points to it."""
    session.exec(delete(BuddyLink).where(BuddyLink.household_id == household.id))
    session.exec(delete(TimelineEvent).where(TimelineEvent.household_id == household.id))
    session.delete(household)
