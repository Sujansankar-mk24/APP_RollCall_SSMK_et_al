"""
Household endpoints:

  POST   /households        a resident registers (opt in)
  GET    /households/{id}   see a household (only if the privacy rules allow it)
  PUT    /households/{id}   the resident updates their profile
  DELETE /households/{id}   "Delete my data": removes it all, immediately
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session

from app.database import get_session
from app.models import Household, TimelineKind, utc_now
from app.privacy import NOT_SHARED_MESSAGE, can_edit_household, can_view_household
from app.schemas import HouseholdIn, HouseholdOut
from app.services.households import apply, delete_everything, to_out
from app.services.timeline import add_household_event
from app.viewer import Viewer, get_viewer

router = APIRouter(prefix="/households", tags=["households"])


def get_or_404(session: Session, household_id: int) -> Household:
    household = session.get(Household, household_id)
    if household is None:
        raise HTTPException(status_code=404, detail="Household not found")
    return household


@router.post("", response_model=HouseholdOut, status_code=201)
def register(data: HouseholdIn, session: Session = Depends(get_session)):
    """Anyone can opt in. The app then acts as this household (its id is returned)."""
    household = Household(contact_name=data.contact_name, address=data.address,
                          latitude=data.latitude, longitude=data.longitude)
    apply(household, data)
    session.add(household)
    session.flush()
    add_household_event(session, household.id, TimelineKind.profile, "Household registered with RollCall")
    session.commit()
    session.refresh(household)
    return to_out(session, household)


@router.get("/{household_id}", response_model=HouseholdOut)
def view(household_id: int, viewer: Viewer = Depends(get_viewer), session: Session = Depends(get_session)):
    household = get_or_404(session, household_id)
    if not can_view_household(session, viewer, household):
        raise HTTPException(status_code=403, detail=NOT_SHARED_MESSAGE[viewer.role])
    return to_out(session, household)


@router.put("/{household_id}", response_model=HouseholdOut)
def update(household_id: int, data: HouseholdIn, viewer: Viewer = Depends(get_viewer),
           session: Session = Depends(get_session)):
    household = get_or_404(session, household_id)
    if not can_edit_household(viewer, household):
        raise HTTPException(status_code=403, detail="Only the resident can change their own profile.")
    apply(household, data)
    household.updated_at = utc_now()
    session.add(household)
    add_household_event(session, household.id, TimelineKind.profile, "Profile updated")
    session.commit()
    session.refresh(household)
    return to_out(session, household)


@router.delete("/{household_id}", status_code=204)
def delete_my_data(household_id: int, viewer: Viewer = Depends(get_viewer),
                   session: Session = Depends(get_session)):
    household = get_or_404(session, household_id)
    if not can_edit_household(viewer, household):
        raise HTTPException(status_code=403, detail="Only the resident can delete their own data.")
    delete_everything(session, household)
    session.commit()
    return Response(status_code=204)
