"""Tests for registering, viewing, editing and deleting a household, and the privacy rules."""

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.main import app
from app.models import BuddyLink, Household, TimelineEvent, Volunteer

client = TestClient(app)

PROFILE = {
    "contact_name": "Test Resident", "phone": "(903) 555-0100", "address": "100 Example Ln", "city": "Greenville",
    "latitude": 33.14, "longitude": -96.11, "seniors": 1, "medical_equipment": ["oxygen"],
    "no_vehicle": True, "language": "es", "wants_buddy": True,
}


def as_(role: str, id: int | None = None) -> dict:
    headers = {"X-Demo-Role": role}
    if id is not None:
        headers["X-Demo-Id"] = str(id)
    return headers


def register(**changes) -> dict:
    response = client.post("/households", json={**PROFILE, **changes})
    assert response.status_code == 201, response.text
    return response.json()


def test_register_returns_the_full_profile():
    body = register()
    assert body["people"] == 1 and body["lives_alone"] is True
    assert body["medical_equipment"] == ["oxygen"] and body["language"] == "es"
    assert body["buddy"] is None


def test_input_is_checked():
    assert client.post("/households", json={**PROFILE, "seniors": 0}).status_code == 422          # nobody lives there
    assert client.post("/households", json={**PROFILE, "medical_equipment": ["jetpack"]}).status_code == 422
    assert client.post("/households", json={**PROFILE, "latitude": 200}).status_code == 422


def test_resident_sees_only_their_own_household():
    mine, theirs = register(), register(contact_name="Neighbor")
    assert client.get(f"/households/{mine['id']}", headers=as_("resident", mine["id"])).status_code == 200
    refused = client.get(f"/households/{theirs['id']}", headers=as_("resident", mine["id"]))
    assert refused.status_code == 403
    assert "only see your own" in refused.json()["detail"]


def test_buddy_sees_only_assigned_households():
    assigned, other = register(), register(contact_name="Other")
    with Session(engine) as session:
        volunteer = Volunteer(name="Test Buddy", latitude=33.1, longitude=-96.1)
        session.add(volunteer)
        session.flush()
        session.add(BuddyLink(volunteer_id=volunteer.id, household_id=assigned["id"]))
        session.commit()
        volunteer_id = volunteer.id
    assert client.get(f"/households/{assigned['id']}", headers=as_("buddy", volunteer_id)).status_code == 200
    assert client.get(f"/households/{other['id']}", headers=as_("buddy", volunteer_id)).status_code == 403
    # The buddy's list contains only their own residents, and only they can ask for it.
    mine = client.get(f"/volunteers/{volunteer_id}/households", headers=as_("buddy", volunteer_id))
    assert [h["id"] for h in mine.json()] == [assigned["id"]]
    assert client.get(f"/volunteers/{volunteer_id}/households", headers=as_("buddy", volunteer_id + 1)).status_code == 403
    assert client.get(f"/volunteers/{volunteer_id}/households", headers=as_("responder")).status_code == 403
    # ...and the resident can see who their buddy is.
    assert client.get(f"/households/{assigned['id']}", headers=as_("resident", assigned["id"])).json()["buddy"]["name"] == "Test Buddy"


def test_responder_sees_nothing_without_an_active_emergency():
    household = register()
    refused = client.get(f"/households/{household['id']}", headers=as_("responder"))
    assert refused.status_code == 403
    assert "active emergency" in refused.json()["detail"]


def test_a_role_is_required():
    household = register()
    assert client.get(f"/households/{household['id']}").status_code == 401


def test_only_the_resident_can_edit():
    mine, theirs = register(), register(contact_name="Neighbor")
    changed = {**PROFILE, "contact_name": "New Name", "children": 2}
    updated = client.put(f"/households/{mine['id']}", json=changed, headers=as_("resident", mine["id"]))
    assert updated.status_code == 200 and updated.json()["people"] == 3
    assert client.put(f"/households/{theirs['id']}", json=changed, headers=as_("resident", mine["id"])).status_code == 403
    assert client.put(f"/households/{mine['id']}", json=changed, headers=as_("responder")).status_code == 403


def test_delete_my_data_removes_everything():
    household = register()
    with Session(engine) as session:
        volunteer = Volunteer(name="Buddy", latitude=33.1, longitude=-96.1)
        session.add(volunteer)
        session.flush()
        session.add(BuddyLink(volunteer_id=volunteer.id, household_id=household["id"]))
        session.commit()
    assert client.delete(f"/households/{household['id']}", headers=as_("resident", household["id"])).status_code == 204
    with Session(engine) as session:
        assert session.get(Household, household["id"]) is None
        assert session.exec(select(BuddyLink).where(BuddyLink.household_id == household["id"])).first() is None
        assert session.exec(select(TimelineEvent).where(TimelineEvent.household_id == household["id"])).first() is None
    assert client.get(f"/households/{household['id']}", headers=as_("resident", household["id"])).status_code == 404


def test_identities_list_only_demo_records():
    register()  # a real (non-demo) registration must never show up here
    assert client.get("/demo/identities").json() == {"households": [], "volunteers": []}
