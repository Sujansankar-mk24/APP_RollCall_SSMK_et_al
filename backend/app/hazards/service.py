"""
Collect live hazards from every source, at most once every few minutes.

Sources are asked at the same time. If one of them is down, the others are
still shown, the last good answer from the failing one is kept, and the app
is told which source had trouble.
"""

import asyncio
from datetime import datetime, timezone
from typing import Optional

import httpx

from app.config import DATA_USER_AGENT, HAZARD_FORCE_MIN_SECONDS, HAZARD_REFRESH_SECONDS
from app.hazards import demo
from app.hazards.models import HazardOut, HazardsOut, SourceStatusOut
from app.hazards.sources import SOURCES, drop_duplicate_fires

NOTE = ("Zones are estimates to help you plan, not official evacuation orders. "
        "Always follow instructions from local officials, and call 911 in an emergency.")


class HazardFeed:
    def __init__(self, sources=SOURCES):
        self.sources = sources
        self.last: dict[str, list[HazardOut]] = {}        # last good answer per source
        self.status: dict[str, SourceStatusOut] = {}
        self.fetched_at: Optional[datetime] = None
        self.lock = asyncio.Lock()

    def is_fresh(self, now: datetime, force: bool = False) -> bool:
        if self.fetched_at is None:
            return False
        age = (now - self.fetched_at).total_seconds()
        # A forced refresh (the app's refresh button) still waits a little
        # between downloads, so tapping it over and over can't flood the sources.
        return age < (HAZARD_FORCE_MIN_SECONDS if force else HAZARD_REFRESH_SECONDS)

    async def refresh(self) -> None:
        async with httpx.AsyncClient(timeout=20, headers={"User-Agent": DATA_USER_AGENT},
                                     follow_redirects=True) as client:
            results = await asyncio.gather(*(fetch(client) for _, fetch in self.sources), return_exceptions=True)
        for (name, _), result in zip(self.sources, results):
            if isinstance(result, BaseException):
                self.status[name] = SourceStatusOut(name=name, ok=False, count=len(self.last.get(name, [])),
                                                    error=str(result)[:160] or type(result).__name__)
            else:
                self.last[name] = result
                self.status[name] = SourceStatusOut(name=name, ok=True, count=len(result))
        self.fetched_at = datetime.now(timezone.utc).replace(microsecond=0)

    async def current(self, force: bool = False) -> HazardsOut:
        now = datetime.now(timezone.utc).replace(microsecond=0)
        async with self.lock:   # if several requests arrive at once, download only once
            if not self.is_fresh(now, force):
                await self.refresh()
        live = [h for items in self.last.values() for h in items
                if h.ends_at is None or h.ends_at > now]           # skip expired alerts
        hazards = demo.hazards(now) + drop_duplicate_fires(live)
        hazards.sort(key=lambda h: -h.level.rank)                  # most serious first
        return HazardsOut(hazards=hazards, sources=[self.status[name] for name, _ in self.sources if name in self.status],
                          updated_at=self.fetched_at or now, note=NOTE)


feed = HazardFeed()
