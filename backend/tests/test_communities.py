"""Neighborhood communities: create, search, ask to join, admin approval."""

from tests.helpers import client, community, sign_up


def test_creator_is_the_admin():
    admin = sign_up()
    created = client.post("/communities", json={"name": "Pecan Hollow", "city": "Greenville"}, headers=admin).json()
    assert created["is_admin"] is True and created["my_status"] == "member" and created["member_count"] == 1
    assert client.get("/me", headers=admin).json()["community"]["name"] == "Pecan Hollow"


def test_search_by_name():
    community(sign_up(), "Pecan Hollow")
    community(sign_up(), "Bluebonnet Ridge")
    found = client.get("/communities", params={"q": "pecan"}, headers=sign_up()).json()
    assert [c["name"] for c in found] == ["Pecan Hollow"]


def test_joining_needs_the_admins_approval():
    admin, newcomer = sign_up(), sign_up("New Neighbor")
    community_id = community(admin)
    asked = client.post(f"/communities/{community_id}/join", headers=newcomer).json()
    assert asked["my_status"] == "pending"
    # A pending member can't see the member list yet.
    assert client.get(f"/communities/{community_id}", headers=newcomer).json()["members"] == []
    details = client.get(f"/communities/{community_id}", headers=admin).json()
    assert [r["name"] for r in details["join_requests"]] == ["New Neighbor"]
    user_id = details["join_requests"][0]["user_id"]
    # Only the admin can approve.
    assert client.post(f"/communities/{community_id}/requests/{user_id}/approve", headers=newcomer).status_code == 403
    approved = client.post(f"/communities/{community_id}/requests/{user_id}/approve", headers=admin).json()
    assert approved["member_count"] == 2
    assert client.get(f"/communities/{community_id}", headers=newcomer).json()["my_status"] == "member"


def test_one_community_at_a_time_and_no_duplicates():
    admin = sign_up()
    community_id = community(admin)
    assert client.post("/communities", json={"name": "Other", "city": "Greenville"}, headers=admin).status_code == 409
    again = client.post("/communities", json={"name": "pecan hollow", "city": "greenville"}, headers=sign_up())
    assert again.status_code == 409 and "already exists" in again.json()["detail"]
    assert client.post(f"/communities/{community_id}/join", headers=admin).status_code == 409


def test_admin_hands_over_when_leaving_and_empty_communities_disappear():
    admin, member = sign_up(), sign_up()
    community_id = community(admin, "Pecan Hollow", member)
    assert client.post(f"/communities/{community_id}/leave", headers=admin).status_code == 204
    assert client.get(f"/communities/{community_id}", headers=member).json()["is_admin"] is True
    client.post(f"/communities/{community_id}/leave", headers=member)
    assert client.get(f"/communities/{community_id}", headers=member).status_code == 404
