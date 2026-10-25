"""
Review first responder applications, and reports about responders.

People apply in the app (Profile > Apply as a first responder) with their
agency, role, badge number, the area they serve and a photo of their ID.
Each application gets an automatic check first (app/services/responder_check.py):
the words on the ID are compared with what they typed, and the agency is looked
up online. It's shown here as a recommendation. There's no public list of who
works where, so a person still makes the decision. The ID photo is deleted as
soon as you decide.

Run from the backend folder:
    python -m scripts.review_responders              list waiting applications and reports
    python -m scripts.review_responders approve 12   approve account 12
    python -m scripts.review_responders reject 12    turn it down
    python -m scripts.review_responders revoke 12    take a responder's access away
    python -m scripts.review_responders done 5       mark report 5 as reviewed
"""

import json
import sys

from sqlmodel import Session, select

from app.config import ID_PHOTOS_DIR
from app.database import create_tables, engine
from app.models import ResponderReport, ResponderStatus, User


def review(user_id: int, approve: bool) -> User:
    """Approve or reject one application, then delete its ID photo."""
    with Session(engine) as session:
        user = session.get(User, user_id)
        if user is None or user.responder_status != ResponderStatus.pending:
            raise ValueError(f"Account {user_id} has no application waiting.")
        user.responder_status = ResponderStatus.approved if approve else ResponderStatus.rejected
        user.is_responder = approve
        if user.responder_id_photo:
            (ID_PHOTOS_DIR / user.responder_id_photo).unlink(missing_ok=True)
            user.responder_id_photo = None
        session.add(user)
        session.commit()
        session.refresh(user)
        return user


def revoke(user_id: int) -> None:
    """Take away someone's responder access (for example after reports)."""
    with Session(engine) as session:
        user = session.get(User, user_id)
        if user is None:
            raise ValueError(f"No account {user_id}.")
        user.is_responder = False
        user.responder_status = ResponderStatus.rejected
        session.add(user)
        session.commit()


def show_waiting() -> None:
    with Session(engine) as session:
        waiting = session.exec(select(User).where(User.responder_status == ResponderStatus.pending)).all()
        print(f"Applications waiting: {len(waiting)}")
        for user in waiting:
            photo = ID_PHOTOS_DIR / user.responder_id_photo if user.responder_id_photo else "(none)"
            print(f"  #{user.id}  {user.name} <{user.email}>")
            print(f"       {user.responder_role}, {user.responder_agency}, serves {user.responder_city}")
            print(f"       badge {user.responder_badge}   ID photo: {photo}")
            print_check(user.responder_check)
        reports = session.exec(select(ResponderReport).where(ResponderReport.reviewed == False)).all()  # noqa: E712
        print(f"\nReports about responders: {len(reports)}")
        for report in reports:
            responder = session.get(User, report.responder_id)
            print(f"  report #{report.id}: {responder.name} (#{responder.id}), {report.reason}. {report.details}")


CHECK_LABELS = {
    "read_text": "Text could be read on the ID",
    "name_on_id": "Their name is on the ID",
    "agency_on_id": "The agency is on the ID",
    "badge_on_id": "The badge number is on the ID",
    "looks_like_responder_id": "It looks like a responder ID",
}


def print_check(saved: str) -> None:
    """The automatic check, as a short checklist."""
    if not saved:
        print("       Automatic check: still running (or the app sent no ID text)")
        return
    check = json.loads(saved)
    print(f"       Automatic check: {check['verdict']}")
    for key, label in CHECK_LABELS.items():
        print(f"         [{'x' if check['checks'].get(key) else ' '}] {label}")
    if check["agency_found_online"]:
        print(f"         [x] Agency found online: {check['agency_found_online']}")
    elif check["online_checked"]:
        print("         [ ] Agency not found online (OpenStreetMap, Wikipedia)")
    else:
        print("         [?] Couldn't search online (no internet)")


def mark_done(report_id: int) -> None:
    with Session(engine) as session:
        report = session.get(ResponderReport, report_id)
        if report is None:
            raise ValueError(f"No report {report_id}.")
        report.reviewed = True
        session.add(report)
        session.commit()


if __name__ == "__main__":
    create_tables()
    if len(sys.argv) == 1:
        show_waiting()
    elif len(sys.argv) == 3 and sys.argv[1] in ("approve", "reject"):
        user = review(int(sys.argv[2]), approve=sys.argv[1] == "approve")
        print(f"{user.name} is now {user.responder_status.value}. Their ID photo was deleted.")
    elif len(sys.argv) == 3 and sys.argv[1] == "revoke":
        revoke(int(sys.argv[2]))
        print("Done. They can no longer mark incidents.")
    elif len(sys.argv) == 3 and sys.argv[1] == "done":
        mark_done(int(sys.argv[2]))
        print("Marked as reviewed.")
    else:
        sys.exit(__doc__)
