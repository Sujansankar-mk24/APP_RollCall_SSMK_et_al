"""
Database connection.

SQLite keeps the whole database in one file (rollcall.db), so there is no
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
    _add_missing_columns()


def _add_missing_columns() -> None:
    """
    create_all() makes new tables but never changes existing ones. When a new
    field is added to a model (like people_down), add the matching column to
    an older database file so it keeps working without a reset.
    """
    with engine.begin() as connection:
        for table in SQLModel.metadata.sorted_tables:
            existing = {row[1] for row in connection.exec_driver_sql(f"PRAGMA table_info('{table.name}')")}
            for column in table.columns:
                if column.name in existing:
                    continue
                column_type = column.type.compile(dialect=engine.dialect)
                default = column.default.arg if column.default is not None and not callable(column.default.arg) else None
                default = getattr(default, "value", default)   # an Enum default is stored as its text
                default_sql = f" DEFAULT {int(default) if isinstance(default, bool) else repr(default)}" if default is not None else ""
                connection.exec_driver_sql(f'ALTER TABLE "{table.name}" ADD COLUMN "{column.name}" {column_type}{default_sql}')


def get_session() -> Iterator[Session]:
    """
    FastAPI "dependency": each API request gets its own database session,
    which is closed automatically when the request finishes.
    """
    with Session(engine) as session:
        yield session
