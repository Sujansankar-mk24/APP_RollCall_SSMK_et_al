"""Shared helpers for the Roll Call tests: make accounts, households, communities."""

from itertools import count

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)
_numbers = count(1)

PROFILE = {
    "contact_name": "Test Resident", "phone": "(903) 555-0100", "address": "100 Example Ln", "city": "Greenville",
    "zip_code": "75401", "latitude": 33.14, "longitude": -96.11, "seniors": 1, "medical_equipment": ["oxygen"],
    "no_vehicle": True, "language": "es", "wants_buddy": True,
}


def ADDRESS_OF(profile: dict = PROFILE) -> dict:
    """The address a volunteer types to ask to check on a household."""
    return {"address": profile["address"], "city": profile["city"], "zip_code": profile["zip_code"]}


def photo(name: str = "photo.jpg") -> dict:
    """A small JPEG to attach to a report (every report needs one)."""
    import cv2
    import numpy as np

    ok, jpeg = cv2.imencode(".jpg", np.full((120, 160, 3), 90, dtype=np.uint8))
    return {"file": (name, jpeg.tobytes(), "image/jpeg")}


def sign_up(name: str = "Test Person") -> dict:
    """A new account. Returns the headers that act as it."""
    n = next(_numbers)
    response = client.post("/auth/signup", json={"name": name, "email": f"person{n}@example.com",
                                                 "password": "correct horse"})
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['token']}"}


def responder(email: str = "chief@example.com") -> dict:
    """A verified first responder. Returns the headers that act as them."""
    from scripts.make_responder import make_responder

    make_responder(email, "a long password", "Alex Rivera")
    token = client.post("/auth/signin", json={"email": email, "password": "a long password"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def register(headers: dict, **changes) -> dict:
    response = client.post("/households", json={**PROFILE, **changes}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def volunteer(headers: dict) -> None:
    assert client.put("/me/volunteer", json={"city": "Greenville"}, headers=headers).status_code == 200


def community(admin: dict, name: str = "Pecan Hollow", *members: dict) -> int:
    """Create a community with `admin`, and let each of `members` join it."""
    created = client.post("/communities", json={"name": name, "city": "Greenville"}, headers=admin)
    assert created.status_code == 201, created.text
    community_id = created.json()["id"]
    for member in members:
        assert client.post(f"/communities/{community_id}/join", headers=member).status_code == 200
        user_id = client.get("/me", headers=member).json()["id"]
        assert client.post(f"/communities/{community_id}/requests/{user_id}/approve", headers=admin).status_code == 200
    return community_id
