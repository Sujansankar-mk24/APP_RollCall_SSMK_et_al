"""
Fill the database with the demo incidents shown on the Map (seed_incidents.py):
reports with photos and videos, checked by the real AI pipeline.

There are no placeholder people, households or communities: those come from
real accounts made in the app. (Responder accounts are issued with
python -m scripts.make_responder.)

Run from the backend folder:
    python -m scripts.reset_demo    (wipe everything, then seed again)
"""

from scripts.seed_incidents import seed_incidents


def seed() -> None:
    seed_incidents()


if __name__ == "__main__":
    seed()
