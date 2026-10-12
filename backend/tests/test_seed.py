"""The demo data must be fictional and realistic."""

from sqlmodel import Session, select

from app.database import engine
from app.models import BuddyLink, Household, Volunteer
from scripts.seed import seed_households


def test_seed_creates_fictional_households_and_buddies():
    seed_households()
    with Session(engine) as session:
        households = session.exec(select(Household)).all()
        volunteers = session.exec(select(Volunteer)).all()
        links = session.exec(select(BuddyLink)).all()
    assert len(households) == 40 and len(volunteers) == 8
    assert all(h.is_demo for h in households)
    # Every phone number is in the 555-01xx range reserved for fiction.
    for phone in [h.phone for h in households] + [h.emergency_contact_phone for h in households] + [v.phone for v in volunteers]:
        assert "555-01" in phone
    # Only households that asked for a buddy get one, and nobody gets two.
    wanted = {h.id for h in households if h.wants_buddy}
    linked = [l.household_id for l in links]
    assert set(linked) <= wanted and len(linked) == len(set(linked))
    assert all(h.people >= 1 for h in households)
