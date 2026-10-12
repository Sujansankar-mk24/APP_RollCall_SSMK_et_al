"""
Volunteer buddy endpoints:

  GET /volunteers/{id}/households   the residents this buddy agreed to check on
                                    (only that buddy can ask; see privacy.py)
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.database import get_session
from app.models import BuddyLink, Household, Volunteer
from app.schemas import HouseholdOut
from app.services.households import to_out
from app.viewer import Role, Viewer, get_viewer

router = APIRouter(prefix="/volunteers", tags=["volunteers"])


@router.get("/{volunteer_id}/households", response_model=list[HouseholdOut])
def my_residents(volunteer_id: int, viewer: Viewer = Depends(get_viewer), session: Session = Depends(get_session)):
    if session.get(Volunteer, volunteer_id) is None:
        raise HTTPException(status_code=404, detail="Volunteer not found")
    if viewer.role != Role.buddy or viewer.id != volunteer_id:
        raise HTTPException(status_code=403, detail="Only the volunteer themselves can see who they check on.")
    households = session.exec(
        select(Household).join(BuddyLink, BuddyLink.household_id == Household.id)
        .where(BuddyLink.volunteer_id == volunteer_id).order_by(Household.city, Household.contact_name)
    ).all()
    return [to_out(session, h) for h in households]
