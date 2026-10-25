"""Profiles, first responder applications and reports, and the Weekly Recap."""

from sqlmodel import Session

from app.config import ID_PHOTOS_DIR
from app.database import engine
from app.models import ResponderStatus, User
from scripts.review_responders import review
from tests.helpers import ADDRESS_OF, client, community, photo, register, responder, sign_up, volunteer


def me(headers: dict) -> dict:
    return client.get("/me", headers=headers).json()


def test_profile_bio_photo_and_away_from_home():
    headers = sign_up("Maya Ortiz")
    updated = client.patch("/me/profile", json={"bio": "Nurse. Happy to help.", "away_from_home": True},
                           headers=headers).json()
    assert updated["bio"] == "Nurse. Happy to help." and updated["away_from_home"] is True
    with_photo = client.put("/me/photo", files=photo(), headers=headers).json()
    assert with_photo["photo_url"].startswith("/media/profiles/")
    assert client.get(with_photo["photo_url"]).status_code == 200
    assert client.delete("/me/photo", headers=headers).json()["photo_url"] is None


def test_profile_photo_must_be_a_picture():
    refused = client.put("/me/photo", files={"file": ("bio.txt", b"hello", "text/plain")}, headers=sign_up())
    assert refused.status_code == 415


def test_neighbors_see_each_others_profiles_but_strangers_dont():
    admin, neighbor, stranger = sign_up("Ana Admin"), sign_up("Nick Neighbor"), sign_up("Sam Stranger")
    community(admin, "Pecan Hollow", neighbor)
    register(neighbor, address="12 Oak St", city="Greenville")
    neighbor_id = me(neighbor)["id"]
    seen = client.get(f"/people/{neighbor_id}", headers=admin).json()
    assert seen["name"] == "Nick Neighbor" and seen["community_name"] == "Pecan Hollow"
    assert seen["address"] == "12 Oak St, Greenville"   # same community: the address is shown
    assert seen["phone"] is None                         # not their buddy: no phone
    assert seen["wants_buddy"] is True and seen["has_buddy"] is False
    assert client.get(f"/people/{neighbor_id}", headers=stranger).status_code == 404


def test_buddies_see_each_others_phone():
    resident, buddy = sign_up(), sign_up()
    register(resident, phone="(903) 555-0142")
    volunteer(buddy)
    client.post("/buddy/requests/address", json=ADDRESS_OF(), headers=buddy)
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    client.post(f"/me/buddy-requests/{request['id']}/accept", headers=resident)
    seen = client.get(f"/people/{me(resident)['id']}", headers=buddy).json()
    assert seen["is_my_buddy"] is True and seen["phone"] == "(903) 555-0142"
    assert seen["address"] is None   # not in the same community


def test_responder_application_is_reviewed_and_the_id_photo_deleted():
    headers = sign_up("Jordan Fields")
    applied = client.post("/me/responder-application", headers=headers, files={"id_photo": ("id.jpg", photo()["file"][1], "image/jpeg")},
                          data={"agency": "Greenville Fire-Rescue", "role": "Firefighter",
                                "badge_number": "GFR-2231", "city": "Greenville"}).json()
    assert applied["responder_status"] == "pending" and applied["is_responder"] is False
    with Session(engine) as session:
        user = session.get(User, applied["id"])
        id_photo = ID_PHOTOS_DIR / user.responder_id_photo
    assert id_photo.exists()
    # Pending applicants can't change incidents yet.
    incident = client.post("/reports", data={"type": "fire", "description": "Grass fire by the road",
                                             "latitude": 33.07, "longitude": -96.1}, files=photo()).json()
    assert client.patch(f"/incidents/{incident['incident_id']}/status", json={"status": "responding"},
                        headers=headers).status_code == 403

    review(applied["id"], approve=True)
    assert not id_photo.exists()                   # deleted as soon as it was reviewed
    assert me(headers)["responder_status"] == "approved" and me(headers)["is_responder"] is True
    listed = client.get("/responders?city=greenville", headers=sign_up()).json()
    assert [r["responder"]["agency"] for r in listed] == ["Greenville Fire-Rescue"]


def test_rejected_application_stays_off_the_list():
    headers = sign_up()
    applied = client.post("/me/responder-application", headers=headers, files={"id_photo": ("id.jpg", photo()["file"][1], "image/jpeg")},
                          data={"agency": "Fake Dept", "role": "Chief", "badge_number": "000", "city": "Greenville"}).json()
    review(applied["id"], approve=False)
    assert me(headers)["responder_status"] == ResponderStatus.rejected.value
    assert client.get("/responders", headers=headers).json() == []


def test_residents_can_report_a_responder():
    chief = responder()
    chief_id = me(chief)["id"]
    resident = sign_up()
    sent = client.post(f"/responders/{chief_id}/report", json={"reason": "reckless", "details": "Closed it too early"},
                       headers=resident)
    assert sent.status_code == 201
    assert client.post(f"/responders/{chief_id}/report", json={"reason": "bored"}, headers=resident).status_code == 422
    # Anyone can open a verified responder's profile.
    assert client.get(f"/people/{chief_id}", headers=resident).json()["responder"]["role"] == "Emergency coordinator"


def test_weekly_recap_photos_need_the_admins_approval():
    admin, member, visitor = sign_up("Ana Admin"), sign_up("Mo Member"), sign_up("Vi Visitor")
    community_id = community(admin, "Pecan Hollow", member)
    added = client.post(f"/communities/{community_id}/recap", files=photo(), data={"caption": "Block party"},
                        headers=member)
    assert added.status_code == 201
    assert added.json()["recap"] == []                         # waiting for the admin
    pending = client.get(f"/communities/{community_id}", headers=admin).json()["pending_photos"]
    assert [p["caption"] for p in pending] == ["Block party"]
    approved = client.post(f"/communities/{community_id}/recap/{pending[0]['id']}/approve", headers=admin).json()
    assert [p["caption"] for p in approved["recap"]] == ["Block party"]
    assert approved["recap"][0]["expires_at"] is not None      # gone after a week...
    pinned = client.post(f"/communities/{community_id}/recap/{pending[0]['id']}/pin", headers=admin).json()
    assert pinned["recap"][0]["pinned"] is True and pinned["recap"][0]["expires_at"] is None   # ...unless pinned
    # People outside the community can see the recap, but not who's in it.
    outside = client.get(f"/communities/{community_id}", headers=visitor).json()
    assert len(outside["recap"]) == 1 and outside["members"] == []
    # Only members can add photos.
    assert client.post(f"/communities/{community_id}/recap", files=photo(), headers=visitor).status_code == 403


def test_members_show_who_has_a_buddy():
    admin, member = sign_up("Ana Admin"), sign_up("Mo Member")
    community_id = community(admin, "Pecan Hollow", member)
    register(member)   # asks for a buddy (wants_buddy in the test profile)
    members = {m["name"]: m for m in client.get(f"/communities/{community_id}", headers=admin).json()["members"]}
    assert members["Mo Member"]["wants_buddy"] is True and members["Mo Member"]["has_buddy"] is False
    assert members["Ana Admin"]["wants_buddy"] is False


def test_members_see_who_checks_on_whom():
    admin, resident, outsider = sign_up("Ana Admin"), sign_up("Rosa Resident"), sign_up("Out Sider")
    community_id = community(admin, "Pecan Hollow", resident)
    register(resident)
    volunteer(admin)
    neighbors = client.get("/buddy/neighbors", headers=admin).json()
    client.post("/buddy/requests/community", json={"household_id": neighbors[0]["household_id"]}, headers=admin)
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    client.post(f"/me/buddy-requests/{request['id']}/accept", headers=resident)
    pairs = client.get(f"/communities/{community_id}", headers=admin).json()["buddy_pairs"]
    assert pairs == [{"volunteer_id": me(admin)["id"], "resident_id": me(resident)["id"]}]
    # People outside the community don't see who checks on whom.
    assert client.get(f"/communities/{community_id}", headers=outsider).json()["buddy_pairs"] == []


def test_members_react_to_recap_photos_with_stickers():
    admin, member = sign_up("Ana Admin"), sign_up("Mo Member")
    community_id = community(admin, "Pecan Hollow", member)
    photo_id = client.post(f"/communities/{community_id}/recap", files=photo(), headers=admin).json()["recap"][0]["id"]
    after = client.post(f"/communities/{community_id}/recap/{photo_id}/react", json={"emoji": "❤️"}, headers=member).json()
    assert after["recap"][0]["reactions"] == [{"emoji": "❤️", "count": 1, "mine": True}]
    assert after["recap"][0]["uploader_name"] == "Ana Admin"
    # The same sticker again takes it off; others aren't allowed.
    again = client.post(f"/communities/{community_id}/recap/{photo_id}/react", json={"emoji": "❤️"}, headers=member).json()
    assert again["recap"][0]["reactions"] == []
    assert client.post(f"/communities/{community_id}/recap/{photo_id}/react", json={"emoji": "💩"},
                       headers=member).status_code == 422


def test_only_members_see_where_neighbors_live():
    admin, member, stranger = sign_up("Ana Admin"), sign_up("Mo Member"), sign_up("Sam Stranger")
    community_id = community(admin, "Pecan Hollow", member)
    register(member, address="12 Oak St", city="Greenville")
    homes = client.get(f"/communities/{community_id}/homes", headers=admin).json()
    assert [(h["name"], h["address"]) for h in homes] == [("Mo Member", "12 Oak St, Greenville")]
    assert client.get(f"/communities/{community_id}/homes", headers=stranger).status_code == 403


def test_checking_in_tells_your_buddy():
    resident, buddy = sign_up(), sign_up()
    register(resident)
    volunteer(buddy)
    client.post("/buddy/requests/address", json=ADDRESS_OF(), headers=buddy)
    request = client.get("/me/buddy-requests", headers=resident).json()[0]
    client.post(f"/me/buddy-requests/{request['id']}/accept", headers=resident)
    checked = client.post("/me/check-in", json={"status": "needs_help"}, headers=resident).json()
    assert checked["check_in"] == "needs_help" and checked["checked_in_at"] is not None
    seen = client.get("/buddy/residents", headers=buddy).json()[0]
    assert seen["check_in"] == "needs_help"
    assert client.post("/me/check-in", json={"status": "maybe"}, headers=resident).status_code == 422
    assert client.post("/me/check-in", json={"status": "safe"}, headers=sign_up()).status_code == 400
