"""
Create a responder account (fire department / emergency coordinator).

Responders can mark incidents responding or resolved and will see households
during an emergency. In the app they apply with their agency, badge number
and an ID photo, and you approve them with scripts/review_responders.py. This
script skips that step, for test and demo accounts.

Run from the backend folder:
    python -m scripts.make_responder responder@example.com "a long password" "Alex Rivera"
(The name is optional.) If the email already has an account, it becomes a
responder account and gets the new password.
"""

import sys

from sqlmodel import Session, select

from app.auth import MIN_PASSWORD_LENGTH, hash_password
from app.database import create_tables, engine
from app.models import ResponderStatus, User


def make_responder(email: str, password: str, name: str = "Responder") -> User:
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ValueError(f"The password needs at least {MIN_PASSWORD_LENGTH} characters.")
    create_tables()
    with Session(engine) as session:
        email = email.strip().lower()
        user = session.exec(select(User).where(User.email == email)).first() or User(name=name, email=email, password_hash="")
        user.password_hash = hash_password(password)
        user.is_responder = True
        user.responder_status = ResponderStatus.approved
        user.responder_agency = user.responder_agency or "Hunt County Emergency Management"
        user.responder_role = user.responder_role or "Emergency coordinator"
        user.responder_city = user.responder_city or "Greenville"
        session.add(user)
        session.commit()
        session.refresh(user)
        return user


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    user = make_responder(*sys.argv[1:4])
    print(f"Responder account ready: {user.email}")
