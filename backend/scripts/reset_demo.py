"""
Wipe all incidents, uploaded media, households and volunteers, then load the
demo data again. Handy before recording the demo video or showing the app to
judges.

Run from the backend folder:
    python -m scripts.reset_demo
(It's fine to leave the server running while you do this.)
"""

from sqlmodel import SQLModel

from app.config import ANNOTATED_DIR, THUMBS_DIR, UPLOADS_DIR
from app.database import create_tables, engine
from scripts.seed import seed


def wipe() -> None:
    # Importing the models registers the tables, then drop them all.
    from app import models  # noqa: F401

    SQLModel.metadata.drop_all(engine)
    create_tables()
    for folder in (UPLOADS_DIR, ANNOTATED_DIR, THUMBS_DIR):
        for path in folder.iterdir():
            if path.is_file():
                path.unlink()


if __name__ == "__main__":
    wipe()
    print("Database and media wiped.")
    seed()
