"""Live hazards: each source's data becomes the right hazards and zones (no internet needed)."""

import asyncio
from datetime import datetime, timedelta, timezone

from app.hazards import demo
from app.hazards.service import HazardFeed
from app.hazards.sources import drop_duplicate_fires, parse_eonet, parse_firms, parse_nws, parse_spc
from app.hazards.zones import HazardKind, ZoneLevel, alert_kind, alert_level, ring_radii
from tests.helpers import client, photo, sign_up

NOW = datetime(2026, 10, 22, 20, 0, tzinfo=timezone.utc)
BOX = {"type": "Polygon", "coordinates": [[[-96.2, 33.0], [-96.0, 33.2], [-95.9, 33.1], [-96.1, 32.9], [-96.2, 33.0]]]}


def test_alert_levels_and_kinds():
    assert alert_level("Tornado Warning", "Extreme") == ZoneLevel.immediate
    assert alert_level("Tornado Watch", "Severe") == ZoneLevel.cautious        # a watch never means "leave now"
    assert alert_level("Severe Thunderstorm Warning", "Severe") == ZoneLevel.evacuate
    assert alert_level("Something New", "Extreme") == ZoneLevel.immediate      # falls back to severity
    assert alert_kind("Tornado Warning") == HazardKind.tornado
    assert alert_kind("Flash Flood Warning") == HazardKind.flood
    assert alert_kind("Air Quality Alert") == HazardKind.air_quality


def test_nws_alert_uses_its_own_area_or_its_zones():
    alerts = {"features": [
        {"id": "a1", "geometry": BOX, "properties": {"event": "Tornado Warning", "severity": "Extreme",
                                                      "status": "Actual", "headline": "Tornado Warning for Hunt County",
                                                      "areaDesc": "Hunt", "ends": "2026-10-22T21:00:00Z"}},
        {"id": "a2", "geometry": None, "properties": {"event": "Air Quality Alert", "severity": "Unknown",
                                                       "status": "Actual", "areaDesc": "Collin; Hunt",
                                                       "affectedZones": ["zone/TXZ104"]}},
        {"id": "a3", "geometry": BOX, "properties": {"event": "Tornado Warning", "status": "Test"}},
    ]}
    hazards = parse_nws(alerts, {"zone/TXZ104": BOX})
    assert [h.title for h in hazards] == ["Tornado Warning", "Air Quality Alert"]   # the test alert is skipped
    warning, air = hazards
    assert warning.level == ZoneLevel.immediate and warning.zones[0].polygon[0] == [33.0, -96.2]   # [lat, lon]
    assert air.level == ZoneLevel.cautious and air.zones[0].polygon


def test_satellite_hot_spots_join_into_fires_sized_by_heat():
    csv = "\n".join([
        "latitude,longitude,acq_date,acq_time,confidence,frp",
        "33.000,-96.000,2026-10-22,1830,n,20",
        "33.005,-96.004,2026-10-22,1830,h,25",     # 0.6 km away: same fire
        "33.500,-96.500,2026-10-22,1830,n,2",      # a small, separate one
        "33.900,-96.900,2026-10-22,1830,l,90",     # low confidence: skipped
    ])
    big, small = sorted(parse_firms(csv), key=lambda h: -len(h.zones))
    assert "2 hot spots" in big.detail
    assert big.level == ZoneLevel.immediate and [z.level for z in big.zones] == list(ZoneLevel)   # 45 MW: all three
    assert small.level == ZoneLevel.cautious and [z.level for z in small.zones] == [ZoneLevel.cautious]


def test_nasa_events_must_be_recent_and_planned_burns_are_calm():
    def event(title, days_ago):
        date = (NOW - timedelta(days=days_ago)).isoformat()
        return {"id": title, "title": title, "categories": [{"id": "wildfires"}],
                "geometry": [{"type": "Point", "coordinates": [-96.1, 33.1], "date": date,
                              "magnitudeValue": 1200, "magnitudeUnit": "acres"}]}
    hazards = parse_eonet({"events": [event("Wildfire Big", 1), event("Prescribed Fire Rx 1", 2),
                                      event("Wildfire Old", 60)]}, now=NOW)
    assert [h.title for h in hazards] == ["Wildfire Big", "Prescribed Fire Rx 1"]
    big, planned = hazards
    assert big.level == ZoneLevel.immediate and big.zones[0].radius_m == ring_radii(HazardKind.fire, 5.0)[ZoneLevel.immediate]
    assert planned.level == ZoneLevel.cautious and len(planned.zones) == 1


def test_storm_reports_keep_texas_and_know_each_table():
    text = "\n".join([
        "Time,F_Scale,Location,County,State,Lat,Lon,Comments",
        "1905,UNK,2 SW Greenville,Hunt,TX,33.11,-96.13,Tornado on the ground. (FWD)",
        "Time,Speed,Location,County,State,Lat,Lon,Comments",
        "1740,70,1 N Quemado,Catron,NM,34.34,-108.49,Wind damage. (ABQ)",
        "Time,Size,Location,County,State,Lat,Lon,Comments",
        "1810,175,Commerce,Hunt,TX,33.25,-95.90,Golf ball hail. (FWD)",
    ])
    tornado, hail = parse_spc(text, today=NOW)
    assert tornado.kind == HazardKind.tornado and tornado.level == ZoneLevel.immediate
    assert hail.title == "Large hail reported" and hail.kind == HazardKind.severe_storm


def test_satellite_spots_on_a_named_fire_are_not_counted_twice():
    named = parse_eonet({"events": [{"id": "x", "title": "Wildfire X", "categories": [{"id": "wildfires"}],
                                     "geometry": [{"type": "Point", "coordinates": [-96.0, 33.0], "date": NOW.isoformat()}]}]},
                        now=NOW)
    spots = parse_firms("latitude,longitude,acq_date,acq_time,confidence,frp\n33.01,-96.01,2026-10-22,1830,n,40")
    assert [h.source for h in drop_duplicate_fires(named + spots)] == ["nasa_eonet"]


def test_one_source_failing_does_not_hide_the_others():
    async def works(client):
        return parse_firms("latitude,longitude,acq_date,acq_time,confidence,frp\n33.0,-96.0,2026-10-22,1830,n,40")

    async def broken(client):
        raise RuntimeError("Weather Service is down")

    out = asyncio.run(HazardFeed(sources=[("Good", works), ("Bad", broken)]).current())
    assert len(out.hazards) == 1
    assert {s.name: s.ok for s in out.sources} == {"Good": True, "Bad": False}
    assert "estimates" in out.note


def test_demo_tornado_warning_looks_real_and_lasts_40_minutes():
    demo.start(NOW)
    (warning,) = demo.hazards(NOW + timedelta(minutes=10))
    assert warning.title == "Tornado Warning" and warning.is_demo and warning.level == ZoneLevel.immediate
    corners = warning.zones[0].polygon
    assert 4 <= len(corners) <= 7                        # like real warnings: a few corners, not a strip
    lats, lons = [c[0] for c in corners], [c[1] for c in corners]
    assert 20 < (max(lats) - min(lats)) * 111 < 60       # tens of km long, like real ones
    assert demo.hazards(NOW + timedelta(minutes=41)) == []
    demo.stop()


def test_demo_warning_endpoints_need_sign_in(monkeypatch):
    from app.hazards import service

    async def nothing(client):
        return []
    monkeypatch.setattr(service, "feed", HazardFeed(sources=[("Quiet", nothing)]))
    from app.routers import hazards as router
    monkeypatch.setattr(router, "feed", service.feed)

    assert client.post("/demo/tornado-warning").status_code == 401
    me = sign_up()
    started = client.post("/demo/tornado-warning", headers=me).json()
    assert [h["title"] for h in started["hazards"]] == ["Tornado Warning"]
    assert client.delete("/demo/tornado-warning", headers=me).status_code == 204
    assert client.get("/hazards").json()["hazards"] == []


def test_community_reports_get_zones_until_resolved():
    report = {"type": "tornado", "latitude": 33.1, "longitude": -96.1, "description": "Funnel cloud"}
    created = client.post("/reports", data=report, files=photo()).json()
    incident = client.get(f"/incidents/{created['incident_id']}").json()
    assert [z["level"] for z in incident["zones"]] == ["immediate", "evacuate", "cautious"]
    assert incident["zones"][0]["radius_m"] == ring_radii(HazardKind.tornado)[ZoneLevel.immediate]
    client.patch(f"/incidents/{created['incident_id']}/status", json={"status": "resolved"})
    assert client.get(f"/incidents/{created['incident_id']}").json()["zones"] == []
