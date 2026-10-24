"""
Profiles: saving profile pictures, working out someone's buddy status, and
building the profile another person is allowed to see.

Who can open whose profile (see can_view_person):
    yourself, people in your own community, your buddy (either way), and
    verified first responders (anyone can see those, so residents know who
    is helping in their area and can report misuse).
What's included depends on who's looking:
    the address only for people in the same community,
    the phone only for their buddy.
"""

import uuid
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from fastapi import HTTPException, UploadFile
from sqlmodel import Session, select

from app.config import MAX_PHOTO_BYTES, MEDIA_DIR, PROFILES_DIR
from app.models import BuddyLink, BuddyStatus, Household, ResponderStatus, User, Volunteer
from app.privacy import community_of, membership, volunteer_of
from app.schemas import PersonOut, ResponderInfoOut
from app.services.incident_views import media_url
from app.services.households import utc


# ---------------------------------------------------------------------------
# Saving pictures
# ---------------------------------------------------------------------------

async def save_picture(upload: UploadFile, folder: Path, max_side: int = 1600) -> Path:
    """
    Check that an upload really is a picture, shrink it, and save it as a
    JPEG in `folder`. Decoding it with OpenCV also strips any hidden data
    (like the GPS location a phone adds to photos).
    """
    data = await upload.read(MAX_PHOTO_BYTES + 1)
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=413, detail="That picture is too big (15 MB at most).")
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise HTTPException(status_code=415, detail="That file isn't a picture. Choose a photo.")
    scale = min(1.0, max_side / max(image.shape[:2]))
    if scale < 1:
        image = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{uuid.uuid4().hex}.jpg"
    cv2.imwrite(str(path), image, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return path


def media_name(path: Path) -> str:
    """The part of a path under media/, e.g. "profiles/ab12.jpg"."""
    return path.relative_to(MEDIA_DIR).as_posix()


def delete_media(name: Optional[str]) -> None:
    if name:
        (MEDIA_DIR / name).unlink(missing_ok=True)


async def save_profile_picture(upload: UploadFile) -> str:
    return media_name(await save_picture(upload, PROFILES_DIR, max_side=800))


# ---------------------------------------------------------------------------
# Buddy status
# ---------------------------------------------------------------------------

def household_of(session: Session, user_id: int) -> Optional[Household]:
    return session.exec(select(Household).where(Household.owner_id == user_id)).first()


def has_active_buddy(session: Session, user_id: int) -> bool:
    """Someone checks on them, or they check on someone."""
    household = household_of(session, user_id)
    if household is not None and session.exec(select(BuddyLink).where(
            BuddyLink.household_id == household.id, BuddyLink.status == BuddyStatus.active)).first():
        return True
    volunteer = session.exec(select(Volunteer).where(Volunteer.user_id == user_id)).first()
    return volunteer is not None and session.exec(select(BuddyLink).where(
        BuddyLink.volunteer_id == volunteer.id, BuddyLink.status == BuddyStatus.active)).first() is not None


def are_buddies(session: Session, a: User, b: User) -> bool:
    """Does one of them check on the other (an accepted buddy match)?"""
    for volunteer_user, resident_user in ((a, b), (b, a)):
        volunteer = volunteer_of(session, volunteer_user)
        household = household_of(session, resident_user.id)
        if volunteer and household and session.exec(select(BuddyLink).where(
                BuddyLink.volunteer_id == volunteer.id, BuddyLink.household_id == household.id,
                BuddyLink.status == BuddyStatus.active)).first():
            return True
    return False


def same_community(session: Session, a: User, b: User) -> bool:
    ca, cb = community_of(session, a.id), community_of(session, b.id)
    return ca is not None and cb is not None and ca.id == cb.id


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------

def is_verified_responder(user: User) -> bool:
    return user.is_responder and user.responder_status in (ResponderStatus.approved, ResponderStatus.none)


def can_view_person(session: Session, viewer: User, person: User) -> bool:
    return (viewer.id == person.id or is_verified_responder(person)
            or same_community(session, viewer, person) or are_buddies(session, viewer, person))


def person_out(session: Session, viewer: User, person: User) -> PersonOut:
    community = community_of(session, person.id)
    m = membership(session, person.id)
    household = household_of(session, person.id)
    buddies = are_buddies(session, viewer, person)
    neighbors = same_community(session, viewer, person) or viewer.id == person.id
    has_buddy = has_active_buddy(session, person.id)

    phone = None
    if buddies or viewer.id == person.id:
        phone = person.phone or (household.phone if household else "") or None
        volunteer = volunteer_of(session, person)
        if phone is None and volunteer is not None and volunteer.phone:
            phone = volunteer.phone

    return PersonOut(
        id=person.id,
        name=person.name,
        photo_url=media_url(person.photo_path),
        bio=person.bio,
        member_since=utc(person.created_at),
        community_id=community.id if community else None,
        community_name=community.name if community else None,
        is_community_admin=bool(community and m and m.is_admin),
        away_from_home=person.away_from_home,
        is_volunteer=volunteer_of(session, person) is not None,
        wants_buddy=bool(household and household.wants_buddy and not has_buddy),
        has_buddy=has_buddy,
        is_my_buddy=buddies,
        responder=ResponderInfoOut(agency=person.responder_agency, role=person.responder_role,
                                   city=person.responder_city) if is_verified_responder(person) else None,
        address=f"{household.address}, {household.city}" if household and neighbors else None,
        phone=phone,
    )
