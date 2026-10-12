"""
Volunteer buddy endpoints.

For volunteers:
  GET    /buddy/residents            the households that accepted them
  GET    /buddy/neighbors            community neighbors who asked for a buddy
  GET    /buddy/requests             requests they've sent
  POST   /buddy/requests/community   ask to check on a neighbor from the list
  POST   /buddy/requests/address     ask to check on someone by typing their address
  DELETE /buddy/requests/{id}        cancel a request, or stop checking on someone

For residents:
  GET    /me/buddy-requests              volunteers asking to check on them
  POST   /me/buddy-requests/{id}/accept  say yes (this volunteer becomes their buddy)
  POST   /me/buddy-requests/{id}/decline say no
  DELETE /me/buddy                       stop having a buddy

Nothing about a household is shared until the resident accepts.
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session, func, select

from app.auth import current_user
from app.database import get_session
from app.models import (
    BuddyLink,
    BuddyStatus,
    CommunityMember,
    Household,
    MemberStatus,
    TimelineKind,
    User,
    Volunteer,
    utc_now,
)
from app.privacy import community_of, outside_buddies_allowed, volunteer_of
from app.schemas import (
    AddressBuddyIn,
    BuddyRequestSent,
    BuddyRequestToMe,
    CommunityBuddyIn,
    HouseholdOut,
    NeighborWantingBuddy,
)
from app.services.accounts import household_of
from app.services.addresses import normalize
from app.services.households import to_out, utc
from app.services.timeline import add_household_event

router = APIRouter(tags=["buddies"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def require_volunteer(session: Session, user: User) -> Volunteer:
    volunteer = volunteer_of(session, user)
    if volunteer is None:
        raise HTTPException(status_code=400, detail="Sign up as a volunteer buddy first.")
    return volunteer


def active_count(session: Session, volunteer: Volunteer) -> int:
    return session.exec(select(func.count()).select_from(BuddyLink).where(
        BuddyLink.volunteer_id == volunteer.id, BuddyLink.status == BuddyStatus.active)).one()


def first_name(household: Household) -> str:
    return household.contact_name.split()[0] if household.contact_name else ""


def sent_out(session: Session, link: BuddyLink) -> BuddyRequestSent:
    if link.typed_address:
        # Typed-address requests only ever show "pending" until accepted. Showing
        # "declined" would tell the volunteer that someone lives there.
        label = link.typed_address
        status = BuddyStatus.active if link.status == BuddyStatus.active else BuddyStatus.pending
    else:
        household = session.get(Household, link.household_id)
        label = f"{first_name(household)} · {household.address}" if household else "A neighbor"
        status = link.status
    return BuddyRequestSent(id=link.id, label=label, status=status, created_at=utc(link.created_at))


# ---------------------------------------------------------------------------
# Volunteers
# ---------------------------------------------------------------------------

@router.get("/buddy/residents", response_model=list[HouseholdOut])
def my_residents(user: User = Depends(current_user), session: Session = Depends(get_session)):
    volunteer = require_volunteer(session, user)
    households = session.exec(
        select(Household).join(BuddyLink, BuddyLink.household_id == Household.id)
        .where(BuddyLink.volunteer_id == volunteer.id, BuddyLink.status == BuddyStatus.active)
        .order_by(Household.city, Household.contact_name)
    ).all()
    return [to_out(session, h) for h in households]


@router.get("/buddy/neighbors", response_model=list[NeighborWantingBuddy])
def neighbors_wanting_a_buddy(user: User = Depends(current_user), session: Session = Depends(get_session)):
    """Members of the volunteer's community who asked for a buddy and don't have one yet."""
    volunteer = require_volunteer(session, user)
    community = community_of(session, user.id)
    if community is None:
        return []
    households = session.exec(
        select(Household).join(CommunityMember, CommunityMember.user_id == Household.owner_id)
        .where(CommunityMember.community_id == community.id, CommunityMember.status == MemberStatus.member,
               Household.wants_buddy, Household.owner_id != user.id)
        .order_by(Household.contact_name)
    ).all()
    links = session.exec(select(BuddyLink).where(BuddyLink.household_id.in_([h.id for h in households]))).all()
    has_buddy = {l.household_id for l in links if l.status == BuddyStatus.active}
    asked = {l.household_id for l in links if l.volunteer_id == volunteer.id}
    return [
        NeighborWantingBuddy(household_id=h.id, first_name=first_name(h), street=h.address, city=h.city,
                             people=h.people, already_asked=h.id in asked)
        for h in households if h.id not in has_buddy
    ]


@router.get("/buddy/requests", response_model=list[BuddyRequestSent])
def my_requests(user: User = Depends(current_user), session: Session = Depends(get_session)):
    volunteer = require_volunteer(session, user)
    links = session.exec(select(BuddyLink).where(
        BuddyLink.volunteer_id == volunteer.id, BuddyLink.status != BuddyStatus.active
    ).order_by(BuddyLink.created_at.desc())).all()
    return [sent_out(session, l) for l in links]


@router.post("/buddy/requests/community", response_model=BuddyRequestSent, status_code=201)
def ask_neighbor(data: CommunityBuddyIn, user: User = Depends(current_user), session: Session = Depends(get_session)):
    volunteer = require_volunteer(session, user)
    household = session.get(Household, data.household_id)
    mine, theirs = community_of(session, user.id), community_of(session, household.owner_id) if household else None
    if household is None or mine is None or theirs is None or mine.id != theirs.id or not household.wants_buddy:
        raise HTTPException(status_code=403, detail="You can only pick neighbors from your own community who asked for a buddy.")
    if household.owner_id == user.id:
        raise HTTPException(status_code=400, detail="That's your own household.")
    if session.exec(select(BuddyLink).where(BuddyLink.volunteer_id == volunteer.id,
                                            BuddyLink.household_id == household.id)).first():
        raise HTTPException(status_code=409, detail="You've already asked to check on them.")
    if active_count(session, volunteer) >= volunteer.capacity:
        raise HTTPException(status_code=409, detail=f"You're already checking on {volunteer.capacity} households, your limit.")
    link = BuddyLink(volunteer_id=volunteer.id, household_id=household.id)
    session.add(link)
    session.commit()
    session.refresh(link)
    return sent_out(session, link)


@router.post("/buddy/requests/address", response_model=BuddyRequestSent, status_code=201)
def ask_by_address(data: AddressBuddyIn, user: User = Depends(current_user), session: Session = Depends(get_session)):
    """
    The answer is the same whether or not the address matches a household, so
    this can't be used to look up who lives where. If it matches (and the
    resident's community allows it), the resident gets the request.
    """
    volunteer = require_volunteer(session, user)
    typed = f"{data.address.strip()}, {data.city.strip()} {data.zip_code}"
    own = household_of(session, user)
    if own is not None and normalize(own.address) == normalize(data.address) and own.zip_code == data.zip_code:
        raise HTTPException(status_code=400, detail="That's your own address.")

    match = None
    for household in session.exec(select(Household).where(Household.zip_code == data.zip_code)).all():
        if normalize(household.address) == normalize(data.address):
            match = household
            break
    if match is not None and not outside_buddies_allowed(session, match, user):
        match = None

    existing = session.exec(select(BuddyLink).where(BuddyLink.volunteer_id == volunteer.id)).all()
    for link in existing:
        if normalize(link.typed_address) == normalize(typed) or (match and link.household_id == match.id):
            return sent_out(session, link)   # already asked; nothing new

    link = BuddyLink(volunteer_id=volunteer.id, household_id=match.id if match else None, typed_address=typed)
    session.add(link)
    session.commit()
    session.refresh(link)
    return sent_out(session, link)


@router.delete("/buddy/requests/{link_id}", status_code=204)
def cancel(link_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    volunteer = require_volunteer(session, user)
    link = session.get(BuddyLink, link_id)
    if link is None or link.volunteer_id != volunteer.id:
        raise HTTPException(status_code=404, detail="Request not found")
    if link.status == BuddyStatus.active and link.household_id:
        add_household_event(session, link.household_id, TimelineKind.buddy, f"{user.name} stopped checking on this household")
    session.delete(link)
    session.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------------------
# Residents
# ---------------------------------------------------------------------------

def my_household_or_400(session: Session, user: User) -> Household:
    household = household_of(session, user)
    if household is None:
        raise HTTPException(status_code=400, detail="Join the roll call first.")
    return household


@router.get("/me/buddy-requests", response_model=list[BuddyRequestToMe])
def requests_to_me(user: User = Depends(current_user), session: Session = Depends(get_session)):
    household = my_household_or_400(session, user)
    mine = community_of(session, user.id)
    links = session.exec(select(BuddyLink).where(
        BuddyLink.household_id == household.id, BuddyLink.status == BuddyStatus.pending
    ).order_by(BuddyLink.created_at)).all()
    out = []
    for link in links:
        volunteer = session.get(Volunteer, link.volunteer_id)
        volunteer_user = session.get(User, volunteer.user_id)
        theirs = community_of(session, volunteer_user.id)
        out.append(BuddyRequestToMe(
            id=link.id, volunteer_name=volunteer_user.name, volunteer_city=volunteer.city,
            same_community=bool(mine and theirs and mine.id == theirs.id), created_at=utc(link.created_at),
        ))
    return out


def my_request_or_404(session: Session, user: User, link_id: int) -> tuple[Household, BuddyLink]:
    household = my_household_or_400(session, user)
    link = session.get(BuddyLink, link_id)
    if link is None or link.household_id != household.id or link.status != BuddyStatus.pending:
        raise HTTPException(status_code=404, detail="Request not found")
    return household, link


@router.post("/me/buddy-requests/{link_id}/accept", response_model=HouseholdOut)
def accept(link_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    """The volunteer becomes this household's buddy (replacing any earlier buddy)."""
    household, link = my_request_or_404(session, user, link_id)
    for old in session.exec(select(BuddyLink).where(
            BuddyLink.household_id == household.id, BuddyLink.status == BuddyStatus.active)).all():
        session.delete(old)
    link.status, link.answered_at = BuddyStatus.active, utc_now()
    household.wants_buddy = True
    session.add_all([link, household])
    volunteer_user = session.get(User, session.get(Volunteer, link.volunteer_id).user_id)
    add_household_event(session, household.id, TimelineKind.buddy, f"{volunteer_user.name} is now this household's buddy")
    session.commit()
    return to_out(session, household)


@router.post("/me/buddy-requests/{link_id}/decline", status_code=204)
def decline(link_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    _, link = my_request_or_404(session, user, link_id)
    link.status, link.answered_at = BuddyStatus.declined, utc_now()
    session.add(link)
    session.commit()
    return Response(status_code=204)


@router.delete("/me/buddy", status_code=204)
def remove_my_buddy(user: User = Depends(current_user), session: Session = Depends(get_session)):
    household = my_household_or_400(session, user)
    for link in session.exec(select(BuddyLink).where(
            BuddyLink.household_id == household.id, BuddyLink.status == BuddyStatus.active)).all():
        session.delete(link)
    add_household_event(session, household.id, TimelineKind.buddy, "The resident ended their buddy match")
    session.commit()
    return Response(status_code=204)
