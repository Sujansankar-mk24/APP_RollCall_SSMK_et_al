"""
A demo Tornado Warning near Greenville, for the demo video and for judges on
a day with no real severe weather. Always labeled "Demo" in the app.

Its shape copies how real National Weather Service tornado warnings look
(checked against archived warnings from the Fort Worth, Norman and Wichita
offices): a polygon that starts at the storm and widens along its expected
path, because the exact track is uncertain, often cut straight along a
county line on one side. Here:
  * the storm is near Caddo Mills, southwest of Greenville, moving northeast
    at 30 mph, and the warning lasts 40 minutes (about 34 km of travel);
  * about 12 km wide at the storm, widening to about 26 km at the far end;
  * the east side stops at a north-south county line.
The icon sits where the tornado is: the storm end of the polygon.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from app.hazards.models import HazardOut, ZoneOut
from app.hazards.zones import HazardKind, ZoneLevel

DURATION = timedelta(minutes=40)

# [latitude, longitude] corners, going around the polygon.
WARNING_AREA = [
    [33.039, -96.308],   # storm end, northwest corner
    [33.319, -96.080],   # far end, northwest corner
    [33.210, -95.950],   # far end, where it meets the county line
    [33.116, -95.950],   # along the county line
    [32.963, -96.217],   # storm end, southeast corner
]
STORM = (33.02, -96.24)

_started: Optional[datetime] = None


def start(now: Optional[datetime] = None) -> None:
    global _started
    _started = (now or datetime.now(timezone.utc)).replace(microsecond=0)   # whole seconds, like every other time


def stop() -> None:
    global _started
    _started = None


def active(now: Optional[datetime] = None) -> bool:
    now = now or datetime.now(timezone.utc)
    return _started is not None and now < _started + DURATION


def hazards(now: Optional[datetime] = None) -> list[HazardOut]:
    if not active(now):
        return []
    return [HazardOut(
        id="demo:tornado-warning",
        source="demo",
        source_label="Demo (not a real alert)",
        kind=HazardKind.tornado,
        title="Tornado Warning",
        detail=("DEMO. A tornado was spotted near Caddo Mills, moving northeast at 30 mph toward Greenville "
                "and Campbell. Take shelter now in an inside room on the lowest floor."),
        level=ZoneLevel.immediate,
        latitude=STORM[0], longitude=STORM[1],
        zones=[ZoneOut(level=ZoneLevel.immediate, polygon=WARNING_AREA)],
        observed_at=_started, ends_at=_started + DURATION, is_demo=True,
    )]
