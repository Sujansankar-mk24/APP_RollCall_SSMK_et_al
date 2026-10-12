"""
Account endpoints:

  POST   /auth/signup     create an account; answers with a sign-in token
  POST   /auth/signin     sign in with email + password; answers with a token
  POST   /auth/signout    forget this device's token
  GET    /me              who am I? (household, volunteer, community)
  PATCH  /me              e.g. "Not now" for the roll call
  PUT    /me/volunteer    agree to check on neighbors
  DELETE /me/volunteer    stop being a volunteer buddy
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session, delete, select

from app.auth import check_password, current_token, current_user, hash_password, issue_token, revoke_token
from app.database import get_session
from app.models import BuddyLink, User, Volunteer
from app.privacy import volunteer_of
from app.schemas import AuthOut, MeOut, MePatch, SignInIn, SignUpIn, VolunteerIn
from app.services.accounts import me_out

router = APIRouter(tags=["accounts"])


@router.post("/auth/signup", response_model=AuthOut, status_code=201)
def sign_up(data: SignUpIn, session: Session = Depends(get_session)):
    if session.exec(select(User).where(User.email == data.email)).first() is not None:
        raise HTTPException(status_code=409, detail="There's already an account with that email. Try signing in.")
    user = User(name=data.name, email=data.email, password_hash=hash_password(data.password))
    session.add(user)
    session.flush()
    token = issue_token(session, user)
    session.commit()
    session.refresh(user)
    return AuthOut(token=token, me=me_out(session, user))


@router.post("/auth/signin", response_model=AuthOut)
def sign_in(data: SignInIn, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == data.email.strip().lower())).first()
    # Same message whether the email or the password was wrong, so nobody can
    # use this to find out which emails have accounts.
    if user is None or not check_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="That email and password don't match.")
    token = issue_token(session, user)
    session.commit()
    return AuthOut(token=token, me=me_out(session, user))


@router.post("/auth/signout", status_code=204)
def sign_out(token: str = Depends(current_token), session: Session = Depends(get_session)):
    revoke_token(session, token)
    session.commit()
    return Response(status_code=204)


@router.get("/me", response_model=MeOut)
def me(user: User = Depends(current_user), session: Session = Depends(get_session)):
    return me_out(session, user)


@router.patch("/me", response_model=MeOut)
def update_me(data: MePatch, user: User = Depends(current_user), session: Session = Depends(get_session)):
    user.roll_call_opt_out = data.roll_call_opt_out
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.put("/me/volunteer", response_model=MeOut)
def become_volunteer(data: VolunteerIn, user: User = Depends(current_user), session: Session = Depends(get_session)):
    if user.is_responder:
        raise HTTPException(status_code=400, detail="Responder accounts can't be volunteer buddies.")
    volunteer = volunteer_of(session, user) or Volunteer(user_id=user.id)
    volunteer.phone, volunteer.city, volunteer.capacity = data.phone, data.city, data.capacity
    session.add(volunteer)
    session.commit()
    return me_out(session, user)


@router.delete("/me/volunteer", response_model=MeOut)
def stop_volunteering(user: User = Depends(current_user), session: Session = Depends(get_session)):
    volunteer = volunteer_of(session, user)
    if volunteer is not None:
        session.exec(delete(BuddyLink).where(BuddyLink.volunteer_id == volunteer.id))
        session.delete(volunteer)
        session.commit()
    return me_out(session, user)
