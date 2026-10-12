"""
The privacy rules: who may see a household's details, and when.

These rules are the heart of RollCall's promise to residents, so they are
written once, here, and every endpoint asks this file before sharing anything.

    The resident ......... always sees and controls their own household.
    Their volunteer buddy  sees only the households they were assigned to
                           (and only if the resident asked for a buddy).
    Responders ........... see a household only while an emergency event is
                           active AND the household is inside that event's zone.
                           (Events are added in step 2; until then, never.)
    Anyone else .......... never.
"""

from sqlmodel import Session, select

from app.models import BuddyLink, Household
from app.viewer import Role, Viewer


def is_buddy_of(session: Session, volunteer_id: int, household_id: int) -> bool:
    link = session.exec(
        select(BuddyLink).where(BuddyLink.volunteer_id == volunteer_id, BuddyLink.household_id == household_id)
    ).first()
    return link is not None


def responder_can_see(session: Session, household: Household) -> bool:
    """Only during an active emergency, only inside its zone. (Events arrive in step 2.)"""
    return False


def can_view_household(session: Session, viewer: Viewer, household: Household) -> bool:
    if viewer.role == Role.resident:
        return viewer.id == household.id
    if viewer.role == Role.buddy:
        return viewer.id is not None and is_buddy_of(session, viewer.id, household.id)
    if viewer.role == Role.responder:
        return responder_can_see(session, household)
    return False


def can_edit_household(viewer: Viewer, household: Household) -> bool:
    """Only the resident can change or delete their own household."""
    return viewer.role == Role.resident and viewer.id == household.id


# A friendly explanation the app can show when access is refused.
NOT_SHARED_MESSAGE = {
    Role.resident: "You can only see your own household.",
    Role.buddy: "You can only see the residents who asked you to check on them.",
    Role.responder: "Household details are only shared during an active emergency, and only for homes inside its zone.",
}
