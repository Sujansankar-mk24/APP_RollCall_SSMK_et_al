"""
Where the live hazards come from. All of these are free public data:

  National Weather Service   official warnings, watches and advisories, with
  (api.weather.gov)          the area each one covers
  NASA FIRMS                 fires seen by the VIIRS satellites in the last
                             couple of days (needs a free key, see config.py)
  NASA EONET                 named wildfires and big events NASA is tracking
  NOAA Storm Prediction      today's confirmed tornado, wind and hail reports
  Center (spc.noaa.gov)

Each source has a parse_... function that turns the source's raw data into
hazards (easy to test with saved sample data), and a fetch_... function that
downloads the data and calls it.
"""

import asyncio
import csv
import io
import json
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx

from app.config import FIRMS_DAYS, FIRMS_MAP_KEY, HAZARD_AREA, HAZARD_CACHE_DIR, HAZARD_STATE
from app.hazards.geometry import centroid, distance_km, geojson_rings, in_area
from app.hazards.models import HazardOut, ZoneOut
from app.hazards.zones import (
    HazardKind,
    ZoneLevel,
    alert_kind,
    alert_level,
    fire_scale_from_acres,
    fire_scale_from_power,
    ring_radii,
)


def rings(kind: HazardKind, scale: float = 1.0) -> list[ZoneOut]:
    """Three circles around a point, most serious first."""
    return [ZoneOut(level=level, radius_m=radius) for level, radius in ring_radii(kind, scale).items()]


def parse_time(text: Optional[str]) -> Optional[datetime]:
    if not text:
        return None
    try:
        moment = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# National Weather Service alerts
# ---------------------------------------------------------------------------
NWS_ALERTS_URL = f"https://api.weather.gov/alerts/active?area={HAZARD_STATE}"
ZONE_CACHE = HAZARD_CACHE_DIR / "nws_zones.json"


def _load_zone_cache() -> dict:
    try:
        return json.loads(ZONE_CACHE.read_text())
    except (OSError, ValueError):
        return {}


def parse_nws(alerts: dict, zone_shapes: dict[str, dict]) -> list[HazardOut]:
    """
    One hazard per alert. An alert's area is its own polygon when it has one
    (warnings usually do); otherwise the shapes of the forecast zones or
    counties it lists (`zone_shapes`: zone URL -> GeoJSON geometry).
    """
    hazards = []
    for feature in alerts.get("features", []):
        p = feature.get("properties", {})
        event = p.get("event") or "Weather alert"
        if p.get("status") not in (None, "Actual"):
            continue   # skip tests and exercises
        outlines = geojson_rings(feature.get("geometry"))
        if not outlines:
            for url in p.get("affectedZones", []):
                outlines += geojson_rings(zone_shapes.get(url))
        if not outlines:
            continue
        level = alert_level(event, p.get("severity"))
        lat, lon = centroid(max(outlines, key=len))
        headline = p.get("headline") or event
        hazards.append(HazardOut(
            id=f"nws:{p.get('id') or feature.get('id')}",
            source="nws",
            source_label="National Weather Service",
            kind=alert_kind(event),
            title=event,
            detail=f"{headline}. Areas: {p.get('areaDesc', '')}."[:400],
            level=level,
            latitude=lat,
            longitude=lon,
            zones=[ZoneOut(level=level, polygon=ring) for ring in outlines],
            observed_at=parse_time(p.get("sent")),
            ends_at=parse_time(p.get("ends") or p.get("expires")),
            link=p.get("@id") or feature.get("id"),
        ))
    return hazards


async def fetch_nws(client: httpx.AsyncClient) -> list[HazardOut]:
    response = await client.get(NWS_ALERTS_URL, headers={"Accept": "application/geo+json"})
    response.raise_for_status()
    alerts = response.json()

    # Download the shapes of any zones we haven't seen before (they never
    # change, so they're saved on disk for next time).
    cache = _load_zone_cache()
    needed = {url for f in alerts.get("features", []) if not f.get("geometry")
              for url in f.get("properties", {}).get("affectedZones", []) if url not in cache}
    limit = asyncio.Semaphore(6)   # don't hammer the Weather Service

    async def zone_shape(url: str):
        async with limit:
            try:
                r = await client.get(url, headers={"Accept": "application/geo+json"})
                return url, r.json().get("geometry") if r.status_code == 200 else None
            except (httpx.HTTPError, ValueError):
                return url, None

    for url, shape in await asyncio.gather(*(zone_shape(u) for u in needed)):
        if shape:
            cache[url] = shape
    if needed:
        try:
            ZONE_CACHE.write_text(json.dumps(cache))
        except OSError:
            pass
    return parse_nws(alerts, cache)


# ---------------------------------------------------------------------------
# NASA FIRMS: fires seen from space
# ---------------------------------------------------------------------------
def firms_url(key: str) -> str:
    west, south, east, north = HAZARD_AREA
    return (f"https://firms.modaps.eosdis.nasa.gov/api/area/csv/{key}/VIIRS_SNPP_NRT/"
            f"{west},{south},{east},{north}/{FIRMS_DAYS}")


def parse_firms(text: str, cluster_km: float = 1.5) -> list[HazardOut]:
    """
    The satellite reports one row per hot spot (375 m wide), so one fire is
    often many rows. Hot spots within `cluster_km` of each other are joined
    into one fire. Low-confidence detections are skipped.
    """
    clusters: list[dict] = []
    for row in csv.DictReader(io.StringIO(text)):
        try:
            lat, lon = float(row["latitude"]), float(row["longitude"])
            power = float(row.get("frp") or 0)
        except (KeyError, ValueError):
            continue
        if row.get("confidence", "n").lower() in ("l", "low"):
            continue
        seen = _firms_time(row)
        for c in clusters:
            if distance_km(lat, lon, c["lat"], c["lon"]) <= cluster_km:
                c["points"] += 1
                c["power"] += power
                c["lat"] += (lat - c["lat"]) / c["points"]   # running average
                c["lon"] += (lon - c["lon"]) / c["points"]
                c["seen"] = max(c["seen"], seen) if c["seen"] and seen else (c["seen"] or seen)
                break
        else:
            clusters.append({"lat": lat, "lon": lon, "points": 1, "power": power, "seen": seen})

    hazards = []
    for c in clusters:
        spots = "1 hot spot" if c["points"] == 1 else f"{c['points']} hot spots"
        level, zones = firms_zones(c["power"])
        hazards.append(HazardOut(
            id=f"firms:{c['lat']:.3f},{c['lon']:.3f}",
            source="nasa_firms",
            source_label="NASA satellites (FIRMS)",
            kind=HazardKind.fire,
            title="Fire seen by satellite",
            detail=(f"NASA's VIIRS satellite detected heat at {spots} here "
                    f"(about {c['power']:.0f} MW). It may be a wildfire, a grass fire, or a controlled burn."),
            level=level,
            latitude=round(c["lat"], 5),
            longitude=round(c["lon"], 5),
            zones=zones,
            observed_at=c["seen"],
            link="https://firms.modaps.eosdis.nasa.gov/map/",
        ))
    return hazards


def firms_zones(power_mw: float) -> tuple[ZoneLevel, list[ZoneOut]]:
    """
    A satellite can't tell a wildfire from a farmer burning a field, so the
    zones follow how much heat it measured:
      under 5 MW    small, often a controlled burn  -> "Be cautious" only
      5 to 30 MW    a real fire                      -> Evacuate + Be cautious
      30 MW or more a big fire                       -> all three levels
    """
    all_rings = rings(HazardKind.fire, fire_scale_from_power(power_mw))
    if power_mw < 5:
        return ZoneLevel.cautious, all_rings[2:]
    if power_mw < 30:
        return ZoneLevel.evacuate, all_rings[1:]
    return ZoneLevel.immediate, all_rings


def _firms_time(row: dict) -> Optional[datetime]:
    try:
        day = datetime.strptime(row["acq_date"], "%Y-%m-%d")
        hhmm = int(row["acq_time"])
        return day.replace(hour=hhmm // 100, minute=hhmm % 100, tzinfo=timezone.utc)
    except (KeyError, ValueError):
        return None


async def fetch_firms(client: httpx.AsyncClient) -> list[HazardOut]:
    if not FIRMS_MAP_KEY:
        return []
    response = await client.get(firms_url(FIRMS_MAP_KEY))
    response.raise_for_status()
    if not response.text.startswith("latitude"):
        raise ValueError(response.text.strip()[:120] or "unexpected answer")   # e.g. "Invalid MAP_KEY"
    return parse_firms(response.text)


# ---------------------------------------------------------------------------
# NASA EONET: named wildfires and big storms
# ---------------------------------------------------------------------------
def eonet_url() -> str:
    west, south, east, north = HAZARD_AREA
    return (f"https://eonet.gsfc.nasa.gov/api/v3/events?status=open"
            f"&bbox={west},{north},{east},{south}")


EONET_KINDS = {"wildfires": HazardKind.fire, "severeStorms": HazardKind.severe_storm, "floods": HazardKind.flood}


EONET_MAX_AGE = timedelta(days=7)


def parse_eonet(data: dict, now: Optional[datetime] = None) -> list[HazardOut]:
    """
    NASA leaves many old fires marked "open" for months, so only events
    updated in the last week are kept.
    """
    now = now or datetime.now(timezone.utc)
    hazards = []
    for event in data.get("events", []):
        categories = [c.get("id") for c in event.get("categories", [])]
        kind = next((EONET_KINDS[c] for c in categories if c in EONET_KINDS), None)
        points = [g for g in event.get("geometry", []) if g.get("type") == "Point"]
        if kind is None or not points:
            continue
        latest = points[-1]
        lon, lat = latest["coordinates"][:2]
        updated = parse_time(latest.get("date"))
        if not in_area(lat, lon, HAZARD_AREA) or updated is None or now - updated > EONET_MAX_AGE:
            continue
        acres = latest.get("magnitudeValue") if (latest.get("magnitudeUnit") or "").lower() == "acres" else None
        size = f" About {acres:,.0f} acres." if acres else ""
        is_planned = "prescribed" in event.get("title", "").lower()
        hazards.append(HazardOut(
            id=f"eonet:{event.get('id')}",
            source="nasa_eonet",
            source_label="NASA EONET",
            kind=kind,
            title=event.get("title", "Wildfire"),
            detail=("A planned, controlled burn tracked by NASA." if is_planned
                    else "An active event tracked by NASA's Earth Observatory.") + size,
            level=ZoneLevel.cautious if is_planned else ZoneLevel.immediate,
            latitude=lat,
            longitude=lon,
            # A planned burn is managed by crews: just a "be cautious" area.
            zones=([ZoneOut(level=ZoneLevel.cautious, radius_m=ring_radii(kind)[ZoneLevel.cautious])] if is_planned
                   else rings(kind, fire_scale_from_acres(acres) if kind == HazardKind.fire else 1.0)),
            observed_at=updated,
            link=(event.get("sources") or [{}])[0].get("url") or event.get("link"),
        ))
    return hazards


async def fetch_eonet(client: httpx.AsyncClient) -> list[HazardOut]:
    response = await client.get(eonet_url())
    response.raise_for_status()
    return parse_eonet(response.json())


# ---------------------------------------------------------------------------
# NOAA Storm Prediction Center: today's storm reports
# ---------------------------------------------------------------------------
SPC_URL = "https://www.spc.noaa.gov/climo/reports/today.csv"
SPC_SECTIONS = {
    "F_Scale": (HazardKind.tornado, "Tornado reported"),
    "Speed": (HazardKind.severe_storm, "Damaging wind reported"),
    "Size": (HazardKind.severe_storm, "Large hail reported"),
}


def parse_spc(text: str, today: Optional[datetime] = None) -> list[HazardOut]:
    """
    The file has three tables one after another (tornado, wind, hail), each
    starting with its own header line. Report times are in UTC.
    """
    today = today or datetime.now(timezone.utc)
    hazards, section = [], None
    for row in csv.reader(io.StringIO(text)):
        if not row:
            continue
        if row[0] == "Time":
            section = SPC_SECTIONS.get(row[1])
            continue
        if section is None or len(row) < 8 or row[4] != HAZARD_STATE:
            continue
        kind, title = section
        try:
            lat, lon = float(row[5]), float(row[6])
            hhmm = int(row[0])
        except ValueError:
            continue
        seen = today.replace(hour=hhmm // 100, minute=hhmm % 100, second=0, microsecond=0)
        if seen > today:
            seen -= timedelta(days=1)   # the SPC "day" starts at 12:00 UTC
        place = f"{row[2].title()}, {row[3].title()} County"
        hazards.append(HazardOut(
            id=f"spc:{kind.value}:{lat:.2f},{lon:.2f}:{hhmm}",
            source="spc",
            source_label="NOAA Storm Prediction Center",
            kind=kind,
            title=title,
            detail=f"{place}. {row[7]}".strip()[:300],
            level=ZoneLevel.immediate if kind == HazardKind.tornado else ZoneLevel.evacuate,
            latitude=lat,
            longitude=lon,
            zones=rings(kind),
            observed_at=seen,
            link="https://www.spc.noaa.gov/climo/reports/today.html",
        ))
    return hazards


async def fetch_spc(client: httpx.AsyncClient) -> list[HazardOut]:
    response = await client.get(SPC_URL)
    response.raise_for_status()
    return parse_spc(response.text)


# ---------------------------------------------------------------------------
# All sources
# ---------------------------------------------------------------------------
SOURCES = [
    ("National Weather Service", fetch_nws),
    ("NASA satellites (FIRMS)", fetch_firms),
    ("NASA EONET", fetch_eonet),
    ("NOAA Storm Prediction Center", fetch_spc),
]


def drop_duplicate_fires(hazards: list[HazardOut], within_km: float = 3.0) -> list[HazardOut]:
    """A named NASA wildfire and the satellite hot spots on top of it are the same fire: keep the named one."""
    named = [h for h in hazards if h.source == "nasa_eonet" and h.kind == HazardKind.fire]
    return [
        h for h in hazards
        if not (h.source == "nasa_firms"
                and any(distance_km(h.latitude, h.longitude, n.latitude, n.longitude) <= within_km for n in named))
    ]
