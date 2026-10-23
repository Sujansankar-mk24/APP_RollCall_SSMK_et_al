"""
Test setup. Runs before any test file is loaded.

Points the app at a temporary database and media folder, so running the tests
never touches the demo data.
"""

import os
import tempfile

_test_dir = tempfile.mkdtemp(prefix="rollcall-tests-")
os.environ["ROLLCALL_DB_PATH"] = os.path.join(_test_dir, "test.db")
os.environ["ROLLCALL_MEDIA_DIR"] = os.path.join(_test_dir, "media")
os.environ["ROLLCALL_CACHE_DIR"] = os.path.join(_test_dir, "cache")
os.environ["FIRMS_MAP_KEY"] = ""   # tests never call the real NASA service

import pytest  # noqa: E402
from sqlmodel import SQLModel  # noqa: E402

from app.database import create_tables, engine  # noqa: E402


@pytest.fixture(autouse=True)
def empty_database():
    """Every test starts with empty tables."""
    from app import models  # noqa: F401

    SQLModel.metadata.drop_all(engine)
    create_tables()
    yield
