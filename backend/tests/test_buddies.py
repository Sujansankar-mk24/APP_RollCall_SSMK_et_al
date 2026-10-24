"""Volunteer buddies: community picks, typed addresses, and the resident's say."""

from tests.helpers import client, community, register, sign_up, volunteer

ADDRESS = {"address": "100 Example Lane", "city": "Greenville", "zip_code": "75401"}


def test_typed_address_gives_the_same_answer_whether_or_not_anyone_lives_there():
    resident, buddy = sign_up(), sign_up()
    register(resident)
    volunteer(buddy)
    real = client.post("/buddy/requests/address", json=ADDRESS, headers=buddy)
    fake = client.post("/buddy/requests/address", json={**ADDRESS, "address": "999 Nowhere Rd"}, headers=buddy)
    assert real.status_code == fake.status_code == 201
    assert real.json()["status"] == fake.json()["status"] == "pending"
    # Only the real household gets a request.
    assert len(client.get("/me/buddy-requests", headers=resident).json()) == 1


def test_declining_an_address_request_is_not_revealed():
    resident, buddy = sign_up(), sign_up()
    register(resident)
    volunteer(buddy)
    client.post("/buddy/requests/address", json=ADDRESS, headers=buddy)
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    assert client.post(f"/me/buddy-requests/{request['id']}/decline", headers=resident).status_code == 204
    assert client.get("/buddy/requests", headers=buddy).json()[0]["status"] == "pending"
    assert client.get("/buddy/residents", headers=buddy).json() == []


def test_only_volunteers_can_ask():
    register(sign_up())
    assert client.post("/buddy/requests/address", json=ADDRESS, headers=sign_up()).status_code == 400


def test_community_neighbors_see_who_wants_a_buddy_with_limited_details():
    admin, buddy, resident = sign_up(), sign_up(), sign_up("Margaret Ellis")
    community(admin, "Pecan Hollow", buddy, resident)
    household = register(resident, contact_name="Margaret Ellis")
    volunteer(buddy)
    neighbors = client.get("/buddy/neighbors", headers=buddy).json()
    assert neighbors == [{"household_id": household["id"], "first_name": "Margaret", "street": "100 Example Ln",
                          "city": "Greenville", "people": 1, "already_asked": False}]
    asked = client.post("/buddy/requests/community", json={"household_id": household["id"]}, headers=buddy)
    assert asked.status_code == 201
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    assert request["same_community"] is True
    client.post(f"/me/buddy-requests/{request['id']}/accept", headers=resident)
    assert [h["id"] for h in client.get("/buddy/residents", headers=buddy).json()] == [household["id"]]


def test_outsiders_cannot_pick_from_a_community_list():
    admin, resident, outsider = sign_up(), sign_up(), sign_up()
    community(admin, "Pecan Hollow", resident)
    household = register(resident)
    volunteer(outsider)
    assert client.get("/buddy/neighbors", headers=outsider).json() == []
    refused = client.post("/buddy/requests/community", json={"household_id": household["id"]}, headers=outsider)
    assert refused.status_code == 403


def test_people_in_a_community_get_buddies_from_it():
    admin, resident, outsider = sign_up(), sign_up(), sign_up()
    community(admin, "Pecan Hollow", resident)
    register(resident)
    volunteer(outsider)
    # Someone outside the community can't become their buddy: the typed
    # address goes nowhere (silently, so nobody learns who lives there).
    client.post("/buddy/requests/address", json=ADDRESS, headers=outsider)
    assert client.get("/me/buddy-requests", headers=resident).json() == []


def test_resident_can_end_the_match():
    resident, buddy = sign_up(), sign_up()
    household = register(resident)
    volunteer(buddy)
    client.post("/buddy/requests/address", json=ADDRESS, headers=buddy)
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    client.post(f"/me/buddy-requests/{request['id']}/accept", headers=resident)
    assert client.delete("/me/buddy", headers=resident).status_code == 204
    assert client.get(f"/households/{household['id']}", headers=buddy).status_code == 403
