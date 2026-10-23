"""Demo data and issuing responder accounts."""

import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import User
from scripts.make_responder import make_responder
from tests.helpers import client, sign_up


def test_make_responder_creates_an_account_that_can_sign_in():
    make_responder("Chief@Example.com", "a long password", "Alex Rivera")
    signed_in = client.post("/auth/signin", json={"email": "chief@example.com", "password": "a long password"})
    assert signed_in.status_code == 200
    assert signed_in.json()["me"]["is_responder"] is True


def test_make_responder_can_upgrade_an_existing_account():
    sign_up("Existing Person")
    with Session(engine) as session:
        email = session.exec(select(User)).one().email
    make_responder(email, "another long password")
    me = client.post("/auth/signin", json={"email": email, "password": "another long password"}).json()["me"]
    assert me["is_responder"] is True


def test_make_responder_needs_a_real_password():
    with pytest.raises(ValueError):
        make_responder("chief@example.com", "short")


def test_responders_cannot_register_a_household():
    make_responder("chief@example.com", "a long password")
    token = client.post("/auth/signin", json={"email": "chief@example.com", "password": "a long password"}).json()["token"]
    refused = client.post("/households", json={"contact_name": "x", "address": "1 A St", "city": "Greenville",
                                               "zip_code": "75401", "latitude": 33.1, "longitude": -96.1, "adults": 1},
                          headers={"Authorization": f"Bearer {token}"})
    assert refused.status_code == 400


def test_there_are_no_demo_account_shortcuts():
    assert client.get("/demo/accounts").status_code == 404
    assert client.post("/demo/signin", json={"user_id": 1}).status_code == 404
