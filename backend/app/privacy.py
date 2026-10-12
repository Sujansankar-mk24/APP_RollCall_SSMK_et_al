"""
The privacy rules: who may see a household's details, and when.

These rules are the heart of RollCall's promise to residents, so they are
written once, here, and every endpoint asks this file before sharing anything.

    The resident ......... always sees and controls their own household.
    Their volunteer buddy  sees a household only after the resident ACCEPTED
                           that buddy's request.
    Responders ........... see a household only while an emergency event is
                           active AND the household is inside that event's zone.
                           (Events are added in step 2; until then, never.)
    Anyone else .......... never. (Community members only see a neighbor's
                           first name and street, and only if that neighbor
                           asked for a buddy.)

And who may become someone's buddy:

    Volunteers in the same community can ask to check on each other.
    Volunteers from outside can only ask if the resident isn't in a community,
    or if their community's admin allows outside buddies. Either way, the
    resident has to accept.
"""

from typing import Optional

from sqlmodel import Session, select

from app.models import BuddyLink, BuddyStatus, Community, CommunityMember, Household, MemberStatus, User, Volunteer


def volunteer_of(session: Session, user: User) -> Optional[Volunteer]:
    return session.exec(select(Volunteer).where(Volunteer.user_id == user.id)).first()


def membership(session: Session, user_id: int) -> Optional[CommunityMember]:
    """The user's community membership (or pending request), if any."""
    return session.exec(select(CommunityMember).where(CommunityMember.user_id == user_id)).first()


def community_of(session: Session, user_id: int) -> Optional[Community]:
    """The community the user is a full member of (not just asking to join)."""
    m = membership(session, user_id)
    if m is None or m.status != MemberStatus.member:
        return None
    return session.get(Community, m.community_id)


def is_active_buddy(session: Session, user: User, household: Household) -> bool:
    volunteer = volunteer_of(session, user)
    if volunteer is None:
        return False
    link = session.exec(select(BuddyLink).where(
        BuddyLink.volunteer_id == volunteer.id,
        BuddyLink.household_id == household.id,
        BuddyLink.status == BuddyStatus.active,
    )).first()
    return link is not None


def responder_can_see(session: Session, household: Household) -> bool:
    """Only during an active emergency, only inside its zone. (Events arrive in step 2.)"""
    return False


def can_view_household(session: Session, user: User, household: Household) -> bool:
    if household.owner_id == user.id:
        return True
    if user.is_responder:
        return responder_can_see(session, household)
    return is_active_buddy(session, user, household)


def can_edit_household(user: User, household: Household) -> bool:
    """Only the resident can change or delete their own household."""
    return household.owner_id == user.id


def outside_buddies_allowed(session: Session, household: Household, volunteer_user: User) -> bool:
    """May this volunteer ask to check on this household?"""
    resident_community = community_of(session, household.owner_id)
    if resident_community is None:
        return True   # not in a community: anyone may ask (the resident still decides)
    volunteer_community = community_of(session, volunteer_user.id)
    if volunteer_community is not None and volunteer_community.id == resident_community.id:
        return True   # neighbors in the same community
    return resident_community.allow_outside_buddies


NOT_SHARED_MESSAGE = "This household's details aren't shared with you."
RESPONDER_MESSAGE = "Household details are only shared during an active emergency, and only for homes inside its zone."
