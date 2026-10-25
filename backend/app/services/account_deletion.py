"""
Leaving a community, and deleting an account with everything attached to it.

Deleting an account removes:
    the household (and its timeline and buddy matches),
    the volunteer sign-up (and everyone they were matched with),
    community membership (the longest-standing member becomes admin, and a
    community with nobody left is removed with its photos),
    Weekly Recap photos they posted and stickers they added,
    reports about responders they sent or received,
    their profile picture and any first responder ID photo,
    every sign-in token, and finally the account itself.
Incident reports aren't tied to accounts, so they stay on the map.
"""

from sqlmodel import Session, col, delete, select

from app.config import ID_PHOTOS_DIR
from app.models import (AuthToken, BuddyLink, Community, CommunityMember, CommunityPhoto, MemberStatus,
                        RecapReaction, ResponderReport, User)
from app.privacy import membership, volunteer_of
from app.services.households import delete_everything
from app.services.people import delete_media, household_of


def delete_photos(session: Session, photos: list[CommunityPhoto]) -> None:
    """Recap photos, their stickers, and the picture files."""
    ids = [p.id for p in photos]
    if ids:
        session.exec(delete(RecapReaction).where(col(RecapReaction.photo_id).in_(ids)))
    for photo in photos:
        delete_media(photo.path)
        session.delete(photo)


def leave_community(session: Session, user: User) -> None:
    """Leave (or stop asking to join) your community. Doesn't commit."""
    m = membership(session, user.id)
    if m is None:
        return
    community = session.get(Community, m.community_id)
    session.delete(m)
    session.flush()
    remaining = session.exec(select(CommunityMember).where(
        CommunityMember.community_id == community.id, CommunityMember.status == MemberStatus.member
    ).order_by(CommunityMember.created_at)).all()
    if not remaining:
        # Nobody left: remove the community, its photos and any requests to join it.
        delete_photos(session, session.exec(select(CommunityPhoto).where(
            CommunityPhoto.community_id == community.id)).all())
        session.exec(delete(CommunityMember).where(CommunityMember.community_id == community.id))
        delete_media(community.photo_path)
        session.delete(community)
    elif m.is_admin and not any(r.is_admin for r in remaining):
        remaining[0].is_admin = True   # the longest-standing member takes over
        community.created_by = remaining[0].user_id
        session.add_all([remaining[0], community])


def delete_account(session: Session, user: User) -> None:
    """Delete the account and everything that belongs to it, then commit."""
    household = household_of(session, user.id)
    if household is not None:
        delete_everything(session, household)

    volunteer = volunteer_of(session, user)
    if volunteer is not None:
        session.exec(delete(BuddyLink).where(BuddyLink.volunteer_id == volunteer.id))
        session.delete(volunteer)

    leave_community(session, user)
    delete_photos(session, session.exec(select(CommunityPhoto).where(CommunityPhoto.uploader_id == user.id)).all())
    session.exec(delete(RecapReaction).where(RecapReaction.user_id == user.id))
    session.exec(delete(ResponderReport).where(
        (ResponderReport.responder_id == user.id) | (ResponderReport.reporter_id == user.id)))

    delete_media(user.photo_path)
    if user.responder_id_photo:
        (ID_PHOTOS_DIR / user.responder_id_photo).unlink(missing_ok=True)
    session.exec(delete(AuthToken).where(AuthToken.user_id == user.id))
    session.delete(user)
    session.commit()
