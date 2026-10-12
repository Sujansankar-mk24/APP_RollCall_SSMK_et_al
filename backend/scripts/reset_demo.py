"""
Wipe all data and load the fictional demo households again. Handy before
recording the demo video or showing the app to judges.

Run from the backend folder:
    python -m scripts.reset_demo
(It's fine to leave the server running while you do this.)
"""

from sqlmodel import SQLModel

from app.database import create_tables, engine
from scripts.seed import seed


def wipe() -> None:
    from app import models  # noqa: F401  (registers the tables)

    SQLModel.metadata.drop_all(engine)
    create_tables()


if __name__ == "__main__":
    wipe()
    print("Database wiped.")
    seed()
