"""The demo data must be fictional, realistic, and follow the privacy rules."""

from sqlmodel import Session, select

from app.database import engine
from app.models import BuddyLink, BuddyStatus, Community, CommunityMember, Household, User, Volunteer
from app.privacy import outside_buddies_allowed
from scripts.seed import seed_households
from tests.helpers import client


def test_seed_creates_fictional_accounts_households_and_communities():
    seed_households()
    with Session(engine) as session:
        households = session.exec(select(Household)).all()
        volunteers = session.exec(select(Volunteer)).all()
        users = session.exec(select(User)).all()
        links = session.exec(select(BuddyLink)).all()
        communities = session.exec(select(Community)).all()
        admins = session.exec(select(CommunityMember).where(CommunityMember.is_admin)).all()
        # Every buddy match follows the community rules.
        for link in links:
            household = session.get(Household, link.household_id)
            volunteer_user = session.get(User, session.get(Volunteer, link.volunteer_id).user_id)
            assert outside_buddies_allowed(session, household, volunteer_user)
    assert len(households) == 40 and len(volunteers) == 8 and len(communities) == 4
    assert all(u.is_demo and u.email.endswith("@example.com") for u in users)
    assert sum(u.is_responder for u in users) == 1
    assert len(admins) == 4   # one admin per community
    for phone in [h.phone for h in households] + [h.emergency_contact_phone for h in households] + [v.phone for v in volunteers]:
        assert "555-01" in phone
    wanted = {h.id for h in households if h.wants_buddy}
    active = [l.household_id for l in links if l.status == BuddyStatus.active]
    assert set(active) <= wanted and len(active) == len(set(active))
    assert any(l.status == BuddyStatus.pending for l in links)   # some still waiting, for the demo


def test_demo_accounts_open_without_a_password_but_real_ones_never_do():
    seed_households()
    accounts = client.get("/demo/accounts").json()
    assert {a["kind"] for a in accounts} == {"resident", "volunteer", "responder"}
    opened = client.post("/demo/signin", json={"user_id": accounts[0]["user_id"]})
    assert opened.status_code == 200 and opened.json()["me"]["is_responder"] is True
    real = client.post("/auth/signup", json={"name": "Real", "email": "real@example.org", "password": "correct horse"})
    assert client.post("/demo/signin", json={"user_id": real.json()["me"]["id"]}).status_code == 403
    assert "Real" not in [a["name"] for a in client.get("/demo/accounts").json()]
