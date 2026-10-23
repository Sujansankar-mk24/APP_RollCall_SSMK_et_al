"""
A demo Tornado Warning over Greenville, for the demo video and for judges on
a day with no real severe weather. Always labeled "Demo" in the app.

It looks like a real National Weather Service warning: a narrow box along the
storm's path (Immediate danger) inside a larger Tornado Watch (Be cautious),
lasting 45 minutes from when it's started.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from app.hazards.models import HazardOut, ZoneOut
from app.hazards.zones import HazardKind, ZoneLevel

DURATION = timedelta(minutes=45)

# The warning box: the storm is southwest of Greenville moving northeast.
WARNING_BOX = [[33.030, -96.260], [33.200, -96.020], [33.160, -95.980], [32.990, -96.215]]
# The watch covers several counties around it.
WATCH_AREA = [[33.55, -96.70], [33.55, -95.55], [32.75, -95.55], [32.75, -96.70]]

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
    ends = _started + DURATION
    return [
        HazardOut(
            id="demo:tornado-watch",
            source="demo",
            source_label="Demo (not a real alert)",
            kind=HazardKind.tornado,
            title="Tornado Watch",
            detail="DEMO. Conditions are right for tornadoes in Hunt, Collin, Fannin and Hopkins counties. Be ready to take shelter.",
            level=ZoneLevel.cautious,
            # Its icon sits in the northwest of the watch, away from the warning's icon.
            latitude=33.42, longitude=-96.48,
            zones=[ZoneOut(level=ZoneLevel.cautious, polygon=WATCH_AREA)],
            observed_at=_started, ends_at=ends, is_demo=True,
        ),
        HazardOut(
            id="demo:tornado-warning",
            source="demo",
            source_label="Demo (not a real alert)",
            kind=HazardKind.tornado,
            title="Tornado Warning",
            detail="DEMO. A tornado was spotted southwest of Greenville moving northeast at 30 mph. Take shelter now in an inside room on the lowest floor.",
            level=ZoneLevel.immediate,
            latitude=33.095, longitude=-96.12,
            zones=[ZoneOut(level=ZoneLevel.immediate, polygon=WARNING_BOX)],
            observed_at=_started, ends_at=ends, is_demo=True,
        ),
    ]
