"""
Danger zones: how much area around a hazard is affected, in three levels.

    Immediate danger   right where it's happening: get away or take shelter now
    Evacuate           close enough that you should leave (or shelter) soon
    Be cautious        stay alert, be ready to act, avoid the area
    (outside those)    normal

Two kinds of shapes:

  * Official warnings (National Weather Service) already come with the exact
    area the forecasters drew. We keep that shape and decide its level from
    the kind of alert, e.g. a Tornado Warning is "Immediate danger" while a
    Tornado Watch is "Be cautious". (ALERT_LEVELS below.)

  * Points (a satellite fire, a storm report, a community report) get three
    rings around them. The ring sizes are rules of thumb per hazard type,
    grown for bigger events. (RINGS below.)

These zones are ESTIMATES to help people plan. They are not official
evacuation orders, and the app says so wherever it shows them.
"""

from enum import Enum


class HazardKind(str, Enum):
    fire = "fire"
    smoke = "smoke"
    tornado = "tornado"
    severe_storm = "severe_storm"   # thunderstorms, hail, damaging wind
    heavy_rain = "heavy_rain"
    flood = "flood"
    hurricane = "hurricane"         # hurricanes, tropical storms, storm surge
    winter_storm = "winter_storm"   # ice, snow, freezing cold
    heat = "heat"
    air_quality = "air_quality"     # smoke, ozone, dust
    injury = "injury"
    other = "other"


class ZoneLevel(str, Enum):
    immediate = "immediate"   # Immediate danger
    evacuate = "evacuate"     # Evacuate
    cautious = "cautious"     # Be cautious

    @property
    def rank(self) -> int:
        """Bigger = more serious (for sorting and picking a hazard's level)."""
        return {"immediate": 3, "evacuate": 2, "cautious": 1}[self.value]


# ---------------------------------------------------------------------------
# Rings around a point: (immediate, evacuate, cautious) radius in meters, for a
# normal-size event. Bigger events multiply these (see ring_radii).
# ---------------------------------------------------------------------------
RINGS: dict[HazardKind, tuple[int, int, int]] = {
    HazardKind.fire:         (500, 1_500, 3_000),    # grass fires spread fast with wind
    HazardKind.smoke:        (300, 1_000, 2_500),
    HazardKind.tornado:      (1_000, 3_000, 8_000),  # the path plus room for it to shift
    HazardKind.severe_storm: (500, 2_000, 5_000),    # hail and downbursts around the core
    HazardKind.heavy_rain:   (300, 1_000, 2_000),
    HazardKind.flood:        (200, 800, 2_000),      # low-water crossings, creeks
    HazardKind.hurricane:    (10_000, 30_000, 80_000),
    HazardKind.winter_storm: (1_000, 3_000, 6_000),
    HazardKind.heat:         (500, 2_000, 5_000),
    HazardKind.air_quality:  (1_000, 3_000, 8_000),
    HazardKind.injury:       (50, 150, 500),         # a crash scene: keep the road clear
    HazardKind.other:        (100, 300, 1_000),
}


def ring_radii(kind: HazardKind, scale: float = 1.0) -> dict[ZoneLevel, int]:
    """The three ring sizes for a hazard, `scale` times the normal size."""
    immediate, evacuate, cautious = RINGS[kind]
    return {
        ZoneLevel.immediate: round(immediate * scale),
        ZoneLevel.evacuate: round(evacuate * scale),
        ZoneLevel.cautious: round(cautious * scale),
    }


def fire_scale_from_power(total_frp_mw: float) -> float:
    """
    How big a satellite-detected fire is, from its Fire Radiative Power (the
    heat the satellite measured, in megawatts): small burns stay at normal
    size, big fires get bigger rings.
    """
    if total_frp_mw >= 100:
        return 3.5
    if total_frp_mw >= 30:
        return 2.0
    if total_frp_mw >= 10:
        return 1.4
    return 1.0


def fire_scale_from_acres(acres: float | None) -> float:
    """How big a named wildfire is, from how many acres have burned."""
    if not acres:
        return 1.5
    if acres >= 1_000:
        return 5.0
    if acres >= 100:
        return 3.0
    return 1.5


# ---------------------------------------------------------------------------
# Official National Weather Service alerts
# ---------------------------------------------------------------------------
# The level for an alert's area, by the words in its name. Checked in order;
# the first match wins. Anything else falls back to the alert's own severity.
ALERT_LEVELS: list[tuple[str, ZoneLevel]] = [
    ("tornado warning", ZoneLevel.immediate),
    ("extreme wind warning", ZoneLevel.immediate),
    ("flash flood emergency", ZoneLevel.immediate),
    ("tornado emergency", ZoneLevel.immediate),
    ("fire warning", ZoneLevel.immediate),
    ("evacuation immediate", ZoneLevel.immediate),
    ("civil danger", ZoneLevel.immediate),
    ("flash flood warning", ZoneLevel.evacuate),
    ("hurricane warning", ZoneLevel.evacuate),
    ("storm surge warning", ZoneLevel.evacuate),
    ("severe thunderstorm warning", ZoneLevel.evacuate),
    ("flood warning", ZoneLevel.evacuate),
    ("ice storm warning", ZoneLevel.evacuate),
    ("blizzard warning", ZoneLevel.evacuate),
    ("excessive heat warning", ZoneLevel.evacuate),
    ("extreme heat warning", ZoneLevel.evacuate),
    # Watches, advisories and statements: be ready, but no need to leave.
    ("watch", ZoneLevel.cautious),
    ("advisory", ZoneLevel.cautious),
    ("statement", ZoneLevel.cautious),
    ("red flag warning", ZoneLevel.cautious),   # fire weather: no fire yet
    ("air quality", ZoneLevel.cautious),
]

SEVERITY_LEVELS = {
    "Extreme": ZoneLevel.immediate,
    "Severe": ZoneLevel.evacuate,
    "Moderate": ZoneLevel.cautious,
    "Minor": ZoneLevel.cautious,
}


def alert_level(event: str, severity: str | None) -> ZoneLevel:
    name = event.lower()
    for words, level in ALERT_LEVELS:
        if words in name:
            return level
    return SEVERITY_LEVELS.get(severity or "", ZoneLevel.cautious)


# What kind of hazard an alert is about, by the words in its name.
ALERT_KINDS: list[tuple[tuple[str, ...], HazardKind]] = [
    (("tornado",), HazardKind.tornado),
    (("hurricane", "tropical", "storm surge"), HazardKind.hurricane),
    (("flood",), HazardKind.flood),
    (("rain",), HazardKind.heavy_rain),
    (("thunderstorm", "wind", "hail", "severe weather"), HazardKind.severe_storm),
    (("winter", "ice", "snow", "freeze", "frost", "blizzard", "cold", "chill", "sleet"), HazardKind.winter_storm),
    (("heat",), HazardKind.heat),
    (("air quality", "smoke", "dust", "ozone"), HazardKind.air_quality),
    (("fire", "red flag"), HazardKind.fire),
]


def alert_kind(event: str) -> HazardKind:
    name = event.lower()
    for words, kind in ALERT_KINDS:
        if any(word in name for word in words):
            return kind
    return HazardKind.other


# ---------------------------------------------------------------------------
# Community reports (Map and Incidents tabs)
# ---------------------------------------------------------------------------
def report_scale(report_count: int) -> float:
    """More people reporting the same thing usually means it's bigger: up to twice the normal size."""
    return min(1 + 0.25 * max(report_count - 1, 0), 2.0)
