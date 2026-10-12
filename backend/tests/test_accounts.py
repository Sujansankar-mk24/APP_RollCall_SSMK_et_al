"""Signing up, signing in and out, and keeping passwords safe."""

from sqlmodel import Session, select

from app.database import engine
from app.models import User
from tests.helpers import client, sign_up

ACCOUNT = {"name": "Jordan Tatum", "email": "Jordan@Example.com", "password": "correct horse"}


def test_sign_up_then_sign_in():
    created = client.post("/auth/signup", json=ACCOUNT)
    assert created.status_code == 201
    assert created.json()["me"]["email"] == "jordan@example.com"   # stored in lowercase
    signed_in = client.post("/auth/signin", json={"email": "jordan@example.com", "password": "correct horse"})
    assert signed_in.status_code == 200 and signed_in.json()["token"] != created.json()["token"]


def test_password_is_never_stored():
    client.post("/auth/signup", json=ACCOUNT)
    with Session(engine) as session:
        stored = session.exec(select(User)).one().password_hash
    assert "correct horse" not in stored and "$" in stored


def test_wrong_password_and_unknown_email_get_the_same_answer():
    client.post("/auth/signup", json=ACCOUNT)
    wrong = client.post("/auth/signin", json={"email": ACCOUNT["email"], "password": "nope nope"})
    unknown = client.post("/auth/signin", json={"email": "nobody@example.com", "password": "nope nope"})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_sign_up_is_checked():
    assert client.post("/auth/signup", json={**ACCOUNT, "password": "short"}).status_code == 422
    assert client.post("/auth/signup", json={**ACCOUNT, "email": "not-an-email"}).status_code == 422
    client.post("/auth/signup", json=ACCOUNT)
    assert client.post("/auth/signup", json=ACCOUNT).status_code == 409   # same email twice


def test_sign_out_forgets_the_token():
    headers = sign_up()
    assert client.get("/me", headers=headers).status_code == 200
    assert client.post("/auth/signout", headers=headers).status_code == 204
    assert client.get("/me", headers=headers).status_code == 401
    assert client.get("/me").status_code == 401


def test_not_now_for_the_roll_call_is_remembered():
    headers = sign_up()
    assert client.patch("/me", json={"roll_call_opt_out": True}, headers=headers).json()["roll_call_opt_out"] is True
    assert client.get("/me", headers=headers).json()["roll_call_opt_out"] is True
