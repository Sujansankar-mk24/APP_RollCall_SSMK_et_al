"""End-to-end tests: call the real API the same way the iPhone app does."""

import cv2
import numpy as np
from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import photo, responder, sign_up

client = TestClient(app)
GREENVILLE = {"latitude": 33.0705, "longitude": -96.1050}


def report(**fields):
    data = {"type": "fire", "description": "Grass fire by the road", **GREENVILLE, **fields}
    return client.post("/reports", data=data, files=photo())


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_first_report_creates_incident_and_second_merges():
    first = report()
    assert first.status_code == 201
    assert first.json()["merged"] is False

    # About 100 m north of the first report.
    second = report(latitude=GREENVILLE["latitude"] + 0.0009, description="Smoke over the road")
    body = second.json()
    assert body["merged"] is True
    assert body["incident_id"] == first.json()["incident_id"]
    assert body["message"] == "Added to existing incident (2 reports)"

    # The test photo is plain gray, so the AI found no fire: it's under review,
    # which only verified first responders see in the list.
    incidents = client.get("/incidents", headers=responder()).json()
    assert len(incidents) == 1 and incidents[0]["report_count"] == 2


def test_missing_location_name_gets_coordinates():
    incident_id = report(location_name="").json()["incident_id"]
    assert client.get(f"/incidents/{incident_id}").json()["location_name"] == "Near 33.0705, -96.1050"


def test_different_type_creates_separate_incident():
    report()
    report(type="flood")
    assert len(client.get("/incidents", headers=responder()).json()) == 2


def test_unconfirmed_report_stays_off_the_map_until_a_responder_reviews_it():
    created = report().json()   # a fire report with a photo that shows no fire
    assert "checking the photo" in created["message"]
    incident_id = created["incident_id"]
    assert client.get("/incidents").json() == []                        # nobody is alerted
    detail = client.get(f"/incidents/{incident_id}").json()
    assert detail["under_review"] is True
    assert "couldn't find" in detail["timeline"][-1]["message"]
    assert client.post(f"/incidents/{incident_id}/review", json={"real": True},
                       headers=sign_up()).status_code == 403             # residents can't
    confirmed = client.post(f"/incidents/{incident_id}/review", json={"real": True}, headers=responder()).json()
    assert confirmed["under_review"] is False
    assert [i["id"] for i in client.get("/incidents").json()] == [incident_id]


def test_dismissed_report_is_closed():
    incident_id = report().json()["incident_id"]
    dismissed = client.post(f"/incidents/{incident_id}/review", json={"real": False}, headers=responder()).json()
    assert dismissed["status"] == "resolved" and dismissed["under_review"] is True
    assert client.get("/incidents").json() == []


def test_weather_reports_go_straight_on_the_map():
    # The AI can't recognize a flood, so those aren't held back.
    report(type="flood", description="Water over the road")
    assert len(client.get("/incidents").json()) == 1


def test_filters():
    report()
    report(type="flood")
    assert [i["type"] for i in client.get("/incidents", params={"type": "flood"}).json()] == ["flood"]
    assert client.get("/incidents", params={"status": "resolved"}).json() == []


def test_detail_has_reports_timeline_and_priority_breakdown():
    incident_id = report().json()["incident_id"]
    detail = client.get(f"/incidents/{incident_id}").json()
    assert detail["reports"][0]["description"] == "Grass fire by the road"
    assert detail["timeline"][0]["kind"] == "report"
    assert detail["priority"]["factors"][0] == {"label": "Fire report", "points": 20}
    assert detail["first_reported_at"].endswith("Z")


def test_status_update_records_time_and_timeline():
    incident_id = report().json()["incident_id"]
    detail = client.patch(f"/incidents/{incident_id}/status", json={"status": "responding"},
                          headers=responder()).json()
    assert detail["status"] == "responding"
    assert detail["responding_at"] is not None
    assert detail["timeline"][-1]["kind"] == "status_change"
    assert "Hunt County Emergency Management" in detail["timeline"][-1]["message"]


def test_only_verified_responders_change_an_incidents_status():
    incident_id = report().json()["incident_id"]
    change = {"status": "resolved"}
    assert client.patch(f"/incidents/{incident_id}/status", json=change).status_code == 401
    assert client.patch(f"/incidents/{incident_id}/status", json=change, headers=sign_up()).status_code == 403


def test_nobody_can_resolve_a_tornado():
    incident_id = report(type="tornado", description="Funnel cloud to the west").json()["incident_id"]
    refused = client.patch(f"/incidents/{incident_id}/status", json={"status": "resolved"}, headers=responder())
    assert refused.status_code == 400
    assert "Nobody can stop" in refused.json()["detail"]


def test_missing_incident_returns_404():
    assert client.get("/incidents/999").status_code == 404


def test_rejects_unknown_type_and_non_media_files():
    assert report(type="volcano").status_code == 422
    response = client.post("/reports", data={"type": "fire", "description": "Grass fire by the road", **GREENVILLE},
                           files={"file": ("notes.txt", b"hello", "text/plain")})
    assert response.status_code == 415


def test_reports_need_a_photo_and_a_description():
    no_photo = client.post("/reports", data={"type": "fire", "description": "Grass fire by the road", **GREENVILLE})
    assert no_photo.status_code == 422
    assert "photo" in no_photo.json()["detail"]
    too_short = report(description="fire")
    assert too_short.status_code == 422
    assert "Describe" in too_short.json()["detail"]
    video = client.post("/reports", data={"type": "fire", "description": "Grass fire by the road", **GREENVILLE},
                        files={"file": ("clip.mp4", b"not really a video", "video/mp4")})
    assert video.status_code == 415


def test_photo_upload_is_analyzed_in_background():
    # A dark, empty photo: the AI should brighten it and find nothing.
    dark = np.full((480, 640, 3), 20, dtype=np.uint8)
    ok, jpeg = cv2.imencode(".jpg", dark)
    response = client.post("/reports", data={"type": "other", "description": "Something at night", **GREENVILLE},
                           files={"file": ("night.jpg", jpeg.tobytes(), "image/jpeg")})
    assert response.status_code == 201

    # TestClient runs background tasks before returning, so the result is ready.
    detail = client.get(f"/incidents/{response.json()['incident_id']}").json()
    analysis = detail["media"][0]["analysis"]
    assert analysis["status"] == "done"
    assert analysis["low_light_used"] is True
    assert analysis["fire_detected"] is False and analysis["people_count"] == 0
    assert analysis["detector"] == "basic detector"
    assert detail["timeline"][-1]["kind"] == "ai_result"
    assert client.get(analysis["annotated_url"]).status_code == 200
