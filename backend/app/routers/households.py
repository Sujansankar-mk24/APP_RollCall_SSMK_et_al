"""
Household endpoints (the signed-in user's own household, plus sharing):

  POST   /households        join the roll call (one household per account)
  GET    /households/{id}   see a household (only if the privacy rules allow it)
  PUT    /households/{id}   the resident updates their profile
  DELETE /households/{id}   "Delete my data": removes it all, immediately
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session

from app.auth import current_user
from app.database import get_session
from app.models import Household, TimelineKind, User, utc_now
from app.privacy import NOT_SHARED_MESSAGE, RESPONDER_MESSAGE, can_edit_household, can_view_household
from app.schemas import HouseholdIn, HouseholdOut
from app.services.accounts import household_of
from app.services.households import apply, delete_everything, to_out
from app.services.timeline import add_household_event

router = APIRouter(prefix="/households", tags=["households"])


def get_or_404(session: Session, household_id: int) -> Household:
    household = session.get(Household, household_id)
    if household is None:
        raise HTTPException(status_code=404, detail="Household not found")
    return household


@router.post("", response_model=HouseholdOut, status_code=201)
def register(data: HouseholdIn, user: User = Depends(current_user), session: Session = Depends(get_session)):
    if user.is_responder:
        raise HTTPException(status_code=400, detail="Responder accounts can't register a household.")
    if household_of(session, user) is not None:
        raise HTTPException(status_code=409, detail="You've already registered your household.")
    household = Household(owner_id=user.id, contact_name=data.contact_name, address=data.address,
                          latitude=data.latitude, longitude=data.longitude)
    apply(household, data)
    user.roll_call_opt_out = False   # they joined after all
    session.add_all([household, user])
    session.flush()
    add_household_event(session, household.id, TimelineKind.profile, "Household joined the roll call")
    session.commit()
    session.refresh(household)
    return to_out(session, household)


@router.get("/{household_id}", response_model=HouseholdOut)
def view(household_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    household = get_or_404(session, household_id)
    if not can_view_household(session, user, household):
        raise HTTPException(status_code=403, detail=RESPONDER_MESSAGE if user.is_responder else NOT_SHARED_MESSAGE)
    return to_out(session, household)


@router.put("/{household_id}", response_model=HouseholdOut)
def update(household_id: int, data: HouseholdIn, user: User = Depends(current_user),
           session: Session = Depends(get_session)):
    household = get_or_404(session, household_id)
    if not can_edit_household(user, household):
        raise HTTPException(status_code=403, detail="Only the resident can change their own profile.")
    apply(household, data)
    household.updated_at = utc_now()
    session.add(household)
    add_household_event(session, household.id, TimelineKind.profile, "Profile updated")
    session.commit()
    session.refresh(household)
    return to_out(session, household)


@router.delete("/{household_id}", status_code=204)
def delete_my_data(household_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    household = get_or_404(session, household_id)
    if not can_edit_household(user, household):
        raise HTTPException(status_code=403, detail="Only the resident can delete their own data.")
    delete_everything(session, household)
    session.commit()
    return Response(status_code=204)
