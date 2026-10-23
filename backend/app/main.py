"""
RollCall backend: the starting point of the web server.

Start it from the backend folder with:
    uvicorn app.main:app --reload
Then open http://localhost:8000/docs to try every endpoint in the browser.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.config import MEDIA_DIR
from app.database import create_tables
from app.routers import accounts, buddies, communities, hazards, households, incidents, reports


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_tables()  # runs once when the server starts
    yield


app = FastAPI(
    title="RollCall API",
    description="Community incident reports checked by AI, plus an emergency roll call so no one gets left behind.",
    version="2.0.0",
    lifespan=lifespan,
)

# Map and Incidents tabs
app.include_router(hazards.router)
app.include_router(incidents.router)
app.include_router(reports.router)
# Accounts
app.include_router(accounts.router)
# Roll Call and Community tabs
app.include_router(households.router)
app.include_router(buddies.router)
app.include_router(communities.router)

# Photos, videos and AI-annotated images are served as plain files, e.g.
# http://localhost:8000/media/annotated/12.jpg
app.mount("/media", StaticFiles(directory=MEDIA_DIR), name="media")


@app.get("/health", tags=["health"])
def health():
    """The app calls this to check that the server is reachable."""
    return {"status": "ok"}
