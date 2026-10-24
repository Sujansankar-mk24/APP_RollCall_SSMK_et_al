"""
Live hazard endpoints (Map tab):

  GET    /hazards                    real alerts, fires and storm reports, with danger zones
                                     (?refresh=true asks the sources again right away)
  POST   /demo/tornado-warning       start the demo Tornado Warning over Greenville (45 min)
  DELETE /demo/tornado-warning       end it early
"""

from fastapi import APIRouter, Depends, Response

from app.auth import current_user
from app.hazards import demo
from app.hazards.models import HazardsOut
from app.hazards.service import feed
from app.models import User

router = APIRouter(tags=["hazards"])


@router.get("/hazards", response_model=HazardsOut)
async def hazards(refresh: bool = False):
    return await feed.current(force=refresh)


@router.post("/demo/tornado-warning", response_model=HazardsOut)
async def start_demo_warning(user: User = Depends(current_user)):
    demo.start()
    return await feed.current()


@router.delete("/demo/tornado-warning", status_code=204)
async def stop_demo_warning(user: User = Depends(current_user)):
    demo.stop()
    return Response(status_code=204)
