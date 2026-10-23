"""
What the API sends for live hazards (GET /hazards). The iOS app has matching
Swift structs in Models/Hazard.swift.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from app.hazards.zones import HazardKind, ZoneLevel


class ZoneOut(BaseModel):
    """
    One danger zone. Either a circle around the hazard's center (radius_m),
    or an exact area (polygon: a list of [latitude, longitude] points).
    """

    level: ZoneLevel
    radius_m: Optional[int] = None
    polygon: Optional[list[list[float]]] = None


class HazardOut(BaseModel):
    id: str                       # stable per source, e.g. "nws:urn:oid:2.49..." or "firms:33.07,-96.10"
    source: str                   # nws, nasa_firms, nasa_eonet, spc, demo
    source_label: str             # "National Weather Service", "NASA satellites", ...
    kind: HazardKind
    title: str                    # "Tornado Warning", "Fire seen by satellite"
    detail: str                   # one or two plain sentences
    level: ZoneLevel              # the most serious zone
    latitude: float               # where to put the icon
    longitude: float
    zones: list[ZoneOut]
    observed_at: Optional[datetime] = None   # when it was seen / issued
    ends_at: Optional[datetime] = None       # when the alert expires
    link: Optional[str] = None               # the official page, for more details
    is_demo: bool = False


class SourceStatusOut(BaseModel):
    name: str
    ok: bool
    count: int
    error: Optional[str] = None


class HazardsOut(BaseModel):
    hazards: list[HazardOut]
    sources: list[SourceStatusOut]
    updated_at: datetime
    note: str   # shown in the app: zones are estimates, follow official instructions
