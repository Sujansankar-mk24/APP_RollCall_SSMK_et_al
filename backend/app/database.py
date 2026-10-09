"""
Database connection.

SQLite keeps the whole database in one file (rescuesight.db), so there is no
database server to install. SQLModel lets us describe tables as Python classes
(see models.py) and query them with Python instead of raw SQL.
"""

from collections.abc import Iterator

from sqlmodel import Session, SQLModel, create_engine

from app.config import DATABASE_PATH

# check_same_thread=False lets FastAPI's worker threads and background AI tasks
# share the connection pool safely (each one still opens its own Session).
engine = create_engine(
    f"sqlite:///{DATABASE_PATH}",
    connect_args={"check_same_thread": False},
)


def create_tables() -> None:
    """Create any tables that don't exist yet. Safe to call every startup."""
    # Importing models registers the table classes with SQLModel.
    from app import models  # noqa: F401

    SQLModel.metadata.create_all(engine)


def get_session() -> Iterator[Session]:
    """
    FastAPI "dependency": each API request gets its own database session,
    which is closed automatically when the request finishes.
    """
    with Session(engine) as session:
        yield session
