"""
Clean up after the UI tests without touching real accounts.

The tests make throwaway accounts (every email ends in @example.com), plus
their households, buddy offers and communities, and they send incident
reports. This removes all of that, puts the Map's demo incidents back the
way seed_incidents.py makes them, and keeps everyone else's account,
household and community. (reset_demo.py, by contrast, wipes everything.)

The test responder (test-responder@example.com) is kept so the tests can
run again right away.

Run from the backend folder:
    python -m scripts.clear_test_data
"""

from sqlmodel import Session, col, delete, select

from app.config import ANNOTATED_DIR, THUMBS_DIR, UPLOADS_DIR
from app.database import engine
from app.models import (
    AuthToken, BuddyLink, Community, CommunityMember, Household, Incident,
    Media, Report, TimelineEvent, User, Volunteer,
)
from scripts.seed_incidents import seed_incidents

TEST_EMAIL_ENDING = "@example.com"
KEEP = {"test-responder@example.com"}


def clear_test_accounts(session: Session) -> int:
    users = session.exec(select(User).where(col(User.email).endswith(TEST_EMAIL_ENDING))).all()
    user_ids = [u.id for u in users if u.email not in KEEP]
    if not user_ids:
        return 0

    households = session.exec(select(Household.id).where(col(Household.owner_id).in_(user_ids))).all()
    volunteers = session.exec(select(Volunteer.id).where(col(Volunteer.user_id).in_(user_ids))).all()
    communities = session.exec(select(Community.id).where(col(Community.created_by).in_(user_ids))).all()

    # Children first, so no row points at something that's already gone.
    session.exec(delete(BuddyLink).where(
        col(BuddyLink.volunteer_id).in_(volunteers) | col(BuddyLink.household_id).in_(households)))
    session.exec(delete(TimelineEvent).where(col(TimelineEvent.household_id).in_(households)))
    session.exec(delete(CommunityMember).where(
        col(CommunityMember.user_id).in_(user_ids) | col(CommunityMember.community_id).in_(communities)))
    session.exec(delete(Community).where(col(Community.id).in_(communities)))
    session.exec(delete(Household).where(col(Household.id).in_(households)))
    session.exec(delete(Volunteer).where(col(Volunteer.id).in_(volunteers)))
    session.exec(delete(AuthToken).where(col(AuthToken.user_id).in_(user_ids)))
    session.exec(delete(User).where(col(User.id).in_(user_ids)))
    return len(user_ids)


def clear_incidents(session: Session) -> None:
    """Remove every incident (and its reports and media), to seed them fresh."""
    session.exec(delete(TimelineEvent).where(col(TimelineEvent.incident_id).is_not(None)))
    session.exec(delete(Media))
    session.exec(delete(Report))
    session.exec(delete(Incident))
    for folder in (UPLOADS_DIR, ANNOTATED_DIR, THUMBS_DIR):
        for path in folder.iterdir():
            if path.is_file():
                path.unlink()


if __name__ == "__main__":
    with Session(engine) as session:
        removed = clear_test_accounts(session)
        clear_incidents(session)
        session.commit()
    print(f"Removed {removed} test accounts and their data. Real accounts were kept.")
    seed_incidents()
