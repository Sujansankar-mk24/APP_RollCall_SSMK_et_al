"""
Fill the database with realistic demo incidents around North Texas
(the Map and Incidents tabs).

Every report goes through the same code as a real report (including merging),
and every photo/video is analyzed by the real AI pipeline. Only the
timestamps are set in the past, so the demo looks like the last 48 hours.

scripts/seed.py runs this together with the demo households. Run from the
backend folder:
    python -m scripts.reset_demo    (wipe everything, then seed again)
"""

import math
import shutil
import sys
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from sqlmodel import Session, select

from app.ai.pipeline import analyze_media
from app.config import LOCAL_TIMEZONE, MEDIA_DIR, SAMPLE_MEDIA_DIR, UPLOADS_DIR
from app.database import create_tables, engine
from app.models import Incident, IncidentStatus, IncidentType, Media, MediaKind, TimelineKind, utc_now
from app.services.incident_views import load_children, to_summary
from app.services.reports import attach_media, create_report
from app.services.timeline import add_event
from scripts import download_samples


@dataclass
class DemoReport:
    minutes_ago: float
    description: str
    north_m: float = 0  # how far from the incident center, in meters (keeps merged pins realistic)
    east_m: float = 0
    sample: Optional[str] = None  # file in sample_media/, if this report had a photo/video


@dataclass
class DemoIncident:
    type: IncidentType
    location_name: str
    latitude: float
    longitude: float
    reports: list[DemoReport]
    # (new status, minutes ago) in order, e.g. [(responding, 90), (resolved, 20)]
    status_changes: list[tuple[IncidentStatus, float]] = field(default_factory=list)


def minutes_since_last_night(hour: int, minute: int) -> float:
    """Minutes since the most recent 'hour:minute' Central Time that is at least 6 hours ago."""
    zone = ZoneInfo(LOCAL_TIMEZONE)
    now_local = datetime.now(zone)
    moment = now_local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    while moment > now_local - timedelta(hours=6):
        moment -= timedelta(days=1)
    return (now_local - moment).total_seconds() / 60


def build_demo_incidents() -> list[DemoIncident]:
    barn_fire = minutes_since_last_night(23, 10)  # a fire reported at 11:10 PM last night
    return [
        DemoIncident(
            IncidentType.fire, "FM 1570 south of Greenville", 33.0705, -96.1050,
            [
                DemoReport(95, "Grass fire spreading along FM 1570. Lots of smoke and the wind is pushing it east.",
                           sample="grass_fire_line.jpg"),
                DemoReport(70, "Flames are close to the fence line by the pasture. Took a video from the road.",
                           north_m=80, east_m=60, sample="grass_fire_clip.mp4"),
                DemoReport(40, "Smoke is blowing across the road and it's hard to see. Drivers are slowing way down.",
                           north_m=-120, east_m=150),
            ],
        ),
        DemoIncident(
            IncidentType.fire, "CR 1200 west of Paris", 33.6420, -95.6230,
            [
                DemoReport(barn_fire, "Barn on fire, flames are huge. People are standing too close.",
                           sample="night_fire_crew.jpg"),
                DemoReport(barn_fire - 8, "Fire is spreading to the brush behind the barn.",
                           north_m=90, east_m=-40, sample="night_fire_training.jpg"),
                DemoReport(barn_fire - 15, "Can see the glow from Highway 82.", north_m=-200, east_m=120),
                DemoReport(barn_fire - 30, "Still burning. Livestock were moved out of the pens.", north_m=40, east_m=70),
            ],
            status_changes=[(IncidentStatus.responding, barn_fire - 20), (IncidentStatus.resolved, barn_fire - 210)],
        ),
        DemoIncident(
            IncidentType.fire, "Field off SH 121 north of Bonham", 33.5950, -96.2010,
            [
                DemoReport(340, "Fire moving fast through the tall grass. Someone in fire gear is out there.",
                           sample="prescribed_burn_texas.jpg"),
                DemoReport(325, "Heavy smoke drifting toward the houses on the east side.", north_m=150, east_m=200),
            ],
            status_changes=[(IncidentStatus.responding, 310)],
        ),
        DemoIncident(
            IncidentType.smoke, "North of Farmersville", 33.1950, -96.3600,
            [
                DemoReport(25, "Big smoke cloud to the north. Can't tell where it's coming from.",
                           sample="smoke_plume.jpg"),
            ],
        ),
        DemoIncident(
            IncidentType.smoke, "Railroad right-of-way east of Commerce", 33.2470, -95.9000,
            [
                DemoReport(2400, "Low smoke and some small flames along the railroad tracks.",
                           sample="controlled_burn_smoke.jpg"),
            ],
            status_changes=[(IncidentStatus.responding, 2370), (IncidentStatus.resolved, 2220)],
        ),
        DemoIncident(
            IncidentType.flood, "Low-water crossing on Post Oak Creek, Sherman", 33.6250, -96.6100,
            [
                DemoReport(180, "Water is over the road at the low-water crossing and a car is stuck in it.",
                           sample="flooded_intersection.jpg"),
                DemoReport(150, "Water is still rising. Someone needs to close this road.", north_m=60, east_m=-90),
            ],
        ),
        DemoIncident(
            IncidentType.injury, "I-30 eastbound near Royse City", 32.9800, -96.3150,
            [
                DemoReport(120, "Two-car crash, one person hurt. People are helping until the ambulance gets here.",
                           sample="crash_medical.jpg"),
                DemoReport(110, "Crash is blocking the right lane.", north_m=-50, east_m=130),
            ],
            status_changes=[(IncidentStatus.responding, 105)],
        ),
        DemoIncident(
            IncidentType.severe_storm, "Church St, Sulphur Springs", 33.1385, -95.6010,
            [
                DemoReport(360, "Strong winds knocked a tree and power lines down across the street. Lines are on the ground.",
                           sample="downed_power_lines.jpg"),
                DemoReport(345, "Power is out on this whole block and hail is coming down.", north_m=110, east_m=-60),
            ],
            status_changes=[(IncidentStatus.responding, 300)],
        ),
        DemoIncident(
            IncidentType.tornado, "FM 815 east of Leonard", 33.3830, -96.2150,
            [
                DemoReport(50, "Funnel cloud touching down southwest of town, moving northeast. Debris in the air."),
                DemoReport(44, "Tornado on the ground, crossed FM 815. Sirens are going off.", north_m=180, east_m=120),
                DemoReport(38, "Barn roof torn off and trees down along the road.", north_m=90, east_m=210),
            ],
        ),
        DemoIncident(
            IncidentType.heavy_rain, "US 380 in Princeton", 33.1800, -96.4980,
            [
                DemoReport(1500, "Very heavy rain, water pooling in the right lane and cars hydroplaning."),
            ],
            status_changes=[(IncidentStatus.resolved, 1380)],
        ),
    ]


def offset(latitude: float, longitude: float, north_m: float, east_m: float) -> tuple[float, float]:
    """Move a GPS point a few meters north/east (1 degree of latitude ~ 111 km)."""
    new_latitude = latitude + north_m / 111_320
    new_longitude = longitude + east_m / (111_320 * math.cos(math.radians(latitude)))
    return round(new_latitude, 6), round(new_longitude, 6)


def copy_sample(name: str) -> str:
    """Copy a sample file into uploads/, like a real upload. Returns its media-relative path."""
    source = SAMPLE_MEDIA_DIR / name
    destination = UPLOADS_DIR / f"{uuid.uuid4().hex}{source.suffix}"
    shutil.copyfile(source, destination)
    return destination.relative_to(MEDIA_DIR).as_posix()


def seed_incidents() -> None:
    create_tables()
    with Session(engine) as session:
        if session.exec(select(Incident)).first() is not None:
            sys.exit("The database already has incidents. Run `python -m scripts.reset_demo` to start over.")

    if download_samples.missing_files():
        print("Downloading sample media first...")
        download_samples.main()

    now = utc_now()
    to_analyze: list[tuple[int, datetime]] = []

    with Session(engine) as session:
        for demo in build_demo_incidents():
            incident = None
            # Oldest report first, exactly like they would have arrived.
            for item in sorted(demo.reports, key=lambda r: -r.minutes_ago):
                at = now - timedelta(minutes=item.minutes_ago)
                latitude, longitude = offset(demo.latitude, demo.longitude, item.north_m, item.east_m)
                incident, report, merged = create_report(
                    session, demo.type, item.description, latitude, longitude, demo.location_name, at=at
                )
                if item.sample:
                    kind = MediaKind.video if item.sample.endswith(".mp4") else MediaKind.photo
                    media = attach_media(session, incident, report, copy_sample(item.sample), kind, at=at)
                    # The AI result appears about a minute after the upload.
                    to_analyze.append((media.id, at + timedelta(seconds=70)))

            for status, minutes_ago in demo.status_changes:
                at = now - timedelta(minutes=minutes_ago)
                incident.status = status
                if status == IncidentStatus.responding:
                    incident.responding_at = at
                    message = "Responders marked this incident as responding"
                else:
                    incident.resolved_at = at
                    message = "Responders marked this incident as resolved"
                add_event(session, incident.id, TimelineKind.status_change, message, at=at)
            session.add(incident)
        session.commit()

    print(f"Created {len(build_demo_incidents())} incidents. Running the AI on {len(to_analyze)} photos/videos...")
    for media_id, at in to_analyze:
        analyze_media(media_id, event_time=at)

    print_summary()


def print_summary() -> None:
    with Session(engine) as session:
        incidents = session.exec(select(Incident)).all()
        reports, media = load_children(session, [i.id for i in incidents])
        rows = [to_summary(i, reports[i.id], media[i.id]) for i in incidents]
        failed = [m for items in media.values() for m in items if m.analysis_error]

    rows.sort(key=lambda s: -s.priority.score)
    print(f"\n{'Priority':<12}{'Type':<14}{'Status':<12}{'Reports':<9}{'AI found':<28}Location")
    for s in rows:
        found = [name for name, hit in (("fire", s.ai.fire_detected), ("smoke", s.ai.smoke_detected)) if hit]
        if s.ai.people_count:
            found.append(f"{s.ai.people_count} {'person' if s.ai.people_count == 1 else 'people'}")
        print(f"{s.priority.score:>3} {s.priority.level:<8}{s.type.label:<14}{s.status.value:<12}"
              f"{s.report_count:<9}{', '.join(found) or 'nothing':<28}{s.location_name}")
    if failed:
        print(f"\nWARNING: {len(failed)} file(s) could not be analyzed: {[m.analysis_error for m in failed]}")


if __name__ == "__main__":
    seed_incidents()
