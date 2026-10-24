"""
Building the "me" summary the app loads after signing in, and deleting an
account's roll call data.
"""

from sqlmodel import Session, select

from app.models import Community, Household, User
from app.privacy import membership, volunteer_of
from app.schemas import MeOut, MyCommunityOut
from app.services.incident_views import media_url


def household_of(session: Session, user: User):
    return session.exec(select(Household).where(Household.owner_id == user.id)).first()


def me_out(session: Session, user: User) -> MeOut:
    household = household_of(session, user)
    m = membership(session, user.id)
    community = session.get(Community, m.community_id) if m else None
    return MeOut(
        id=user.id,
        name=user.name,
        email=user.email,
        is_responder=user.is_responder,
        roll_call_opt_out=user.roll_call_opt_out,
        household_id=household.id if household else None,
        is_volunteer=volunteer_of(session, user) is not None,
        community=MyCommunityOut(id=community.id, name=community.name, city=community.city,
                                 status=m.status, is_admin=m.is_admin) if community else None,
        is_demo=user.is_demo,
        bio=user.bio,
        photo_url=media_url(user.photo_path),
        phone=user.phone,
        away_from_home=user.away_from_home,
        responder_status=user.responder_status,
        responder_agency=user.responder_agency,
        responder_role=user.responder_role,
        responder_city=user.responder_city,
    )
