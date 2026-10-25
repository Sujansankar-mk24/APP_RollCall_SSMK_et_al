"""
Profiles and first responders:

  PATCH  /me/profile                   your name, bio, phone, "away from home"
  PUT    /me/photo                     your profile picture (a photo upload)
  DELETE /me/photo                     remove it
  POST   /me/check-in                  "I'm safe" or "I need help" (from the app, a
                                       notification, or the Lock Screen)
  GET    /people/{user_id}             someone's profile (see app/services/people.py
                                       for who can see what), with their buddy
                                       connections in your community
  POST   /people/{user_id}/buddy-offer offer to be their volunteer buddy (same
                                       community only; they accept or decline)
  POST   /me/responder-application     apply as a first responder: agency, role,
                                       badge number, area, and a photo of your ID
  GET    /responders?city=Greenville   verified first responders (in an area)
  POST   /responders/{user_id}/report  flag a responder as fake, abusive or reckless

First responder applications are reviewed by a person (the app's admin) with
python -m scripts.review_responders. There's no government database to check
IDs against, so a human looks at each one. The ID photo is kept out of
media/ (never shared) and deleted right after the review.
"""

from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from sqlmodel import Session, func, select

from app.auth import current_user
from app.config import ID_PHOTOS_DIR, MAX_TEXT_LENGTH
from app.database import engine, get_session
from app.models import BuddyLink, CommunityMember, MemberStatus, ResponderReport, ResponderStatus, User, Volunteer
from app.models import TimelineKind, utc_now
from app.privacy import community_of, volunteer_of
from app.routers.communities import buddy_pairs, member_out
from app.schemas import CheckInIn, HouseholdOut, MeOut, PersonOut, ProfilePatch, ResponderReportIn
from app.services.households import to_out
from app.services.responder_check import check_application
from app.services.timeline import add_household_event
from app.services.accounts import me_out
from app.services.people import (buddy_offer_status, can_view_person, delete_media, household_of,
                                 is_verified_responder, person_out, same_community, save_picture,
                                 save_profile_picture)

router = APIRouter(tags=["people"])


@router.patch("/me/profile", response_model=MeOut)
def update_profile(data: ProfilePatch, user: User = Depends(current_user), session: Session = Depends(get_session)):
    if data.name is not None:
        user.name = data.name.strip()
    if data.bio is not None:
        user.bio = data.bio.strip()
    if data.phone is not None:
        user.phone = data.phone.strip()
    if data.away_from_home is not None:
        user.away_from_home = data.away_from_home
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.put("/me/photo", response_model=MeOut)
async def set_photo(file: UploadFile = File(...), user: User = Depends(current_user),
                    session: Session = Depends(get_session)):
    new_name = await save_profile_picture(file)
    delete_media(user.photo_path)
    user.photo_path = new_name
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.delete("/me/photo", response_model=MeOut)
def remove_photo(user: User = Depends(current_user), session: Session = Depends(get_session)):
    delete_media(user.photo_path)
    user.photo_path = None
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.post("/me/check-in", response_model=HouseholdOut)
def check_in(data: CheckInIn, user: User = Depends(current_user), session: Session = Depends(get_session)):
    """Tell your buddy (and, in an emergency, responders) that you're safe or need help."""
    household = household_of(session, user.id)
    if household is None:
        raise HTTPException(status_code=400, detail="Join the roll call first, so there's a household to check in.")
    household.check_in, household.checked_in_at = data.status, utc_now()
    session.add(household)
    add_household_event(session, household.id, TimelineKind.check_in,
                        "Checked in: safe" if data.status == "safe" else "Checked in: needs help")
    session.commit()
    session.refresh(household)
    return to_out(session, household)


@router.get("/people/{user_id}", response_model=PersonOut)
def person(user_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    other = session.get(User, user_id)
    # The same answer for "no such person" and "not shared with you", so this
    # can't be used to find out who has an account.
    if other is None or not can_view_person(session, user, other):
        raise HTTPException(status_code=404, detail="This profile isn't shared with you.")
    return with_connections(session, user, other)


def with_connections(session: Session, viewer: User, person: User) -> PersonOut:
    """
    The profile plus the person's buddy connections, for the bubble web on it.
    Only for people in your own community, and only matches inside it (the
    same pairs the community's connections web already shows its members).
    """
    out = person_out(session, viewer, person)
    community = community_of(session, person.id)
    if community is None or not (viewer.id == person.id or same_community(session, viewer, person)):
        return out
    rows = session.exec(select(CommunityMember, User).join(User, User.id == CommunityMember.user_id).where(
        CommunityMember.community_id == community.id, CommunityMember.status == MemberStatus.member)).all()
    pairs = [p for p in buddy_pairs(session, [u.id for _, u in rows])
             if person.id in (p.volunteer_id, p.resident_id)]
    linked = {person.id} | {p.volunteer_id for p in pairs} | {p.resident_id for p in pairs}
    out.connections = [member_out(session, m, u) for m, u in rows if u.id in linked]
    out.connection_pairs = pairs
    return out


@router.post("/people/{user_id}/buddy-offer", response_model=PersonOut, status_code=201)
def offer_to_be_buddy(user_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    """
    "Be their buddy" on someone's profile. It's a request: they accept or
    decline in Roll Call, and nothing about their household is shared until
    they accept. If you aren't a volunteer yet, this signs you up as one.
    """
    other = session.get(User, user_id)
    if other is None or not can_view_person(session, user, other):
        raise HTTPException(status_code=404, detail="This profile isn't shared with you.")
    status = buddy_offer_status(session, user, other)
    if status == "none":
        raise HTTPException(status_code=403, detail="You can offer to be a buddy for people in your own community "
                                                    "who joined the roll call.")
    if status in ("asked", "checking_on"):
        return with_connections(session, user, other)   # already done, nothing new
    volunteer = volunteer_of(session, user)
    if volunteer is None:
        community = community_of(session, user.id)
        volunteer = Volunteer(user_id=user.id, phone=user.phone, city=community.city if community else "")
        session.add(volunteer)
        session.flush()
    active = session.exec(select(func.count()).select_from(BuddyLink).where(
        BuddyLink.volunteer_id == volunteer.id, BuddyLink.status == "active")).one()
    if active >= volunteer.capacity:
        raise HTTPException(status_code=409, detail=f"You're already checking on {volunteer.capacity} households, your limit.")
    session.add(BuddyLink(volunteer_id=volunteer.id, household_id=household_of(session, other.id).id))
    session.commit()
    return with_connections(session, user, other)


# ---------------------------------------------------------------------------
# First responders
# ---------------------------------------------------------------------------

@router.post("/me/responder-application", response_model=MeOut)
async def apply_as_responder(
    background: BackgroundTasks,
    agency: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    role: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    badge_number: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    city: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    id_photo: UploadFile = File(...),
    # The words the iPhone read on the ID (with Apple's Vision, on the phone).
    id_text: str = Form("", max_length=4000),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    if is_verified_responder(user):
        raise HTTPException(status_code=400, detail="You're already a verified first responder.")
    saved = await save_picture(id_photo, ID_PHOTOS_DIR)
    if user.responder_id_photo:
        (ID_PHOTOS_DIR / user.responder_id_photo).unlink(missing_ok=True)   # replace an older application
    user.responder_status = ResponderStatus.pending
    user.responder_agency, user.responder_role = agency.strip(), role.strip()
    user.responder_badge, user.responder_city = badge_number.strip(), city.strip()
    user.responder_id_photo = saved.name
    user.responder_check = ""
    session.add(user)
    session.commit()
    # The automatic check (the ID's words and an internet search for the
    # agency) runs after answering, so the app doesn't wait for it.
    background.add_task(run_responder_check, user.id, id_text)
    return me_out(session, user)


def run_responder_check(user_id: int, id_text: str) -> None:
    with Session(engine) as session:
        check_application(session, user_id, id_text)


@router.get("/responders", response_model=list[PersonOut])
def responders(city: Optional[str] = None, user: User = Depends(current_user),
               session: Session = Depends(get_session)):
    query = select(User).where(User.is_responder == True)  # noqa: E712 (SQL needs ==)
    if city:
        query = query.where(func.lower(User.responder_city) == city.strip().lower())
    people = [p for p in session.exec(query.order_by(User.name)).all() if is_verified_responder(p)]
    return [person_out(session, user, p) for p in people]


@router.post("/responders/{responder_id}/report", status_code=201)
def report_responder(responder_id: int, data: ResponderReportIn, user: User = Depends(current_user),
                     session: Session = Depends(get_session)):
    responder = session.get(User, responder_id)
    if responder is None or not is_verified_responder(responder):
        raise HTTPException(status_code=404, detail="First responder not found.")
    if responder.id == user.id:
        raise HTTPException(status_code=400, detail="You can't report yourself.")
    session.add(ResponderReport(responder_id=responder.id, reporter_id=user.id,
                                reason=data.reason, details=data.details.strip()))
    session.commit()
    return {"message": "Thanks. Your report will be reviewed. It isn't shared with the responder."}
