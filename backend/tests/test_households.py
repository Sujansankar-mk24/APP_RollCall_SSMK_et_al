"""Joining the roll call, and who can see, edit and delete a household."""

from sqlmodel import Session, select

from app.auth import issue_token
from app.database import engine
from app.models import BuddyLink, Household, TimelineEvent, User
from tests.helpers import PROFILE, client, register, sign_up, volunteer


def test_join_returns_the_full_profile():
    me = sign_up()
    body = register(me)
    assert body["people"] == 1 and body["lives_alone"] is True
    assert body["medical_equipment"] == ["oxygen"] and body["zip_code"] == "75401"
    assert client.get("/me", headers=me).json()["household_id"] == body["id"]


def test_one_household_per_account():
    me = sign_up()
    register(me)
    assert client.post("/households", json=PROFILE, headers=me).status_code == 409


def test_input_is_checked():
    me = sign_up()
    assert client.post("/households", json={**PROFILE, "seniors": 0}, headers=me).status_code == 422
    assert client.post("/households", json={**PROFILE, "medical_equipment": ["jetpack"]}, headers=me).status_code == 422
    assert client.post("/households", json={**PROFILE, "zip_code": "7540"}, headers=me).status_code == 422
    assert client.post("/households", json={**PROFILE, "city": ""}, headers=me).status_code == 422


def test_signing_in_is_required():
    assert client.post("/households", json=PROFILE).status_code == 401
    household = register(sign_up())
    assert client.get(f"/households/{household['id']}").status_code == 401


def test_people_see_only_their_own_household():
    me, neighbor = sign_up(), sign_up()
    mine, theirs = register(me), register(neighbor)
    assert client.get(f"/households/{mine['id']}", headers=me).status_code == 200
    assert client.get(f"/households/{theirs['id']}", headers=me).status_code == 403


def test_a_buddy_sees_a_household_only_after_the_resident_accepts():
    resident, buddy = sign_up(), sign_up("Test Buddy")
    household = register(resident)
    volunteer(buddy)
    client.post("/buddy/requests/address", json={"address": "100 example lane", "city": "Greenville",
                                                 "zip_code": "75401"}, headers=buddy)
    assert client.get(f"/households/{household['id']}", headers=buddy).status_code == 403
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    client.post(f"/me/buddy-requests/{request['id']}/accept", headers=resident)
    assert client.get(f"/households/{household['id']}", headers=buddy).status_code == 200
    assert client.get(f"/households/{household['id']}", headers=resident).json()["buddy"]["name"] == "Test Buddy"


def test_responder_sees_nothing_without_an_active_emergency():
    household = register(sign_up())
    with Session(engine) as session:
        responder = User(name="Responder", email="r@example.com", password_hash="issued", is_responder=True)
        session.add(responder)
        session.flush()
        headers = {"Authorization": f"Bearer {issue_token(session, responder)}"}
        session.commit()
    refused = client.get(f"/households/{household['id']}", headers=headers)
    assert refused.status_code == 403
    assert "active emergency" in refused.json()["detail"]
    # Responder accounts are issued, not signed up for: there's no password to guess.
    assert client.post("/auth/signin", json={"email": "r@example.com", "password": "issued"}).status_code == 401


def test_only_the_resident_can_edit():
    me, neighbor = sign_up(), sign_up()
    mine, theirs = register(me), register(neighbor)
    changed = {**PROFILE, "contact_name": "New Name", "children": 2}
    updated = client.put(f"/households/{mine['id']}", json=changed, headers=me)
    assert updated.status_code == 200 and updated.json()["people"] == 3
    assert client.put(f"/households/{theirs['id']}", json=changed, headers=me).status_code == 403


def test_delete_my_data_removes_everything():
    resident, buddy = sign_up(), sign_up()
    household = register(resident)
    volunteer(buddy)
    client.post("/buddy/requests/address", json={"address": "100 Example Ln", "city": "Greenville",
                                                 "zip_code": "75401"}, headers=buddy)
    assert client.delete(f"/households/{household['id']}", headers=resident).status_code == 204
    with Session(engine) as session:
        assert session.get(Household, household["id"]) is None
        assert session.exec(select(BuddyLink).where(BuddyLink.household_id == household["id"])).first() is None
        assert session.exec(select(TimelineEvent).where(TimelineEvent.household_id == household["id"])).first() is None
    assert client.get("/me", headers=resident).json()["household_id"] is None
