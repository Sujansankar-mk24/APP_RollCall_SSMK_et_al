"""
Demo accounts, for judges and the demo video.

The sign-in screen lists a few fictional accounts (a resident, a volunteer
buddy, a responder, ...) that can be opened with one tap, no password.
This ONLY works for accounts marked is_demo by the seed script; a real
account someone creates in the app can never be opened this way.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.auth import issue_token
from app.database import get_session
from app.models import Community, Household, User, Volunteer
from app.privacy import community_of
from app.schemas import AuthOut, DemoAccount, DemoAccountLogin
from app.services.accounts import me_out

router = APIRouter(prefix="/demo", tags=["demo"])


@router.get("/accounts", response_model=list[DemoAccount])
def demo_accounts(session: Session = Depends(get_session)):
    users = session.exec(select(User).where(User.is_demo).order_by(User.name)).all()
    households = {h.owner_id: h for h in session.exec(select(Household)).all()}
    volunteers = {v.user_id: v for v in session.exec(select(Volunteer)).all()}
    # Featured: the responder, plus the admin and a volunteer of the first
    # community, so the demo shows neighbors in the same neighborhood.
    first = session.exec(select(Community).where(Community.is_demo).order_by(Community.id)).first()
    featured_ids = {u.id for u in users if u.is_responder}
    if first is not None:
        featured_ids.add(first.created_by)
        volunteer_ids = [u.id for u in users if u.id in volunteers and community_of(session, u.id) == first]
        featured_ids.update(volunteer_ids[:1])
    out = []
    for user in users:
        community = community_of(session, user.id)
        place = (households[user.id].city if user.id in households
                 else volunteers[user.id].city if user.id in volunteers else "")
        detail = " · ".join(part for part in (place, community.name if community else "") if part)
        if user.is_responder:
            kind = "responder"
        elif user.id in volunteers:
            kind = "volunteer"
        else:
            kind = "resident"
        out.append(DemoAccount(user_id=user.id, name=user.name, kind=kind, detail=detail,
                               featured=user.id in featured_ids))
    order = {"responder": 0, "volunteer": 1, "resident": 2}
    return sorted(out, key=lambda a: (order[a.kind], a.detail, a.name))


@router.post("/signin", response_model=AuthOut)
def demo_sign_in(data: DemoAccountLogin, session: Session = Depends(get_session)):
    user = session.get(User, data.user_id)
    if user is None or not user.is_demo:
        raise HTTPException(status_code=403, detail="Only demo accounts can be opened without a password.")
    token = issue_token(session, user)
    session.commit()
    return AuthOut(token=token, me=me_out(session, user))
