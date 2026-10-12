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
from app.routers import demo, households, volunteers


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_tables()  # runs once when the server starts
    yield


app = FastAPI(
    title="RollCall API",
    description="Emergency roll call: make sure no one gets left behind.",
    version="2.0.0",
    lifespan=lifespan,
)

app.include_router(households.router)
app.include_router(volunteers.router)
app.include_router(demo.router)

# Photos attached to check-ins are served as plain files.
app.mount("/media", StaticFiles(directory=MEDIA_DIR), name="media")


@app.get("/health", tags=["health"])
def health():
    """The app calls this to check that the server is reachable."""
    return {"status": "ok"}
