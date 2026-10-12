"""
Demo-only endpoints. RollCall has no real accounts yet, so the app's role
switcher asks here which (fictional) households and volunteers it can act as.
Only demo records are listed; a household someone registers in the app never
appears here.
"""

from fastapi import APIRouter, Depends
from sqlmodel import Session, func, select

from app.database import get_session
from app.models import BuddyLink, Household, Volunteer
from app.schemas import DemoHousehold, DemoIdentities, DemoVolunteer

router = APIRouter(prefix="/demo", tags=["demo"])


@router.get("/identities", response_model=DemoIdentities)
def identities(session: Session = Depends(get_session)):
    households = session.exec(select(Household).where(Household.is_demo).order_by(Household.city, Household.contact_name)).all()
    volunteers = session.exec(select(Volunteer).where(Volunteer.is_demo).order_by(Volunteer.name)).all()
    counts = dict(session.exec(select(BuddyLink.volunteer_id, func.count()).group_by(BuddyLink.volunteer_id)).all())
    return DemoIdentities(
        households=[DemoHousehold(id=h.id, contact_name=h.contact_name, city=h.city) for h in households],
        volunteers=[DemoVolunteer(id=v.id, name=v.name, city=v.city, assigned=counts.get(v.id, 0)) for v in volunteers],
    )
