"""
Does a report's photo actually show what was reported?

Two checks work together:
  * On the phone, Apple's Vision framework labels the whole scene ("snow",
    "storm", "fire", "bedroom", ...). The app sends those labels with the
    report, so the photo is checked without any extra upload.
  * On the server, YOLO looks for flames, smoke and people.

A report counts as confirmed only when the photo shows the disaster
itself: snow or ice for a winter storm, a storm sky or funnel for a
tornado, flames or smoke for a fire. People in the photo are never
enough on their own (a selfie in a bedroom isn't a winter storm). An
indoor scene with no disaster in it is never confirmed.
"""

from typing import Optional

from app.models import IncidentType, Media

# What the phone's scene labels must include for each kind of report, and
# how sure the label has to be (0 to 1).
SCENE_RULES: dict[IncidentType, dict[str, float]] = {
    IncidentType.fire: {"fire": 0.25, "flame": 0.25},
    IncidentType.smoke: {"fire": 0.25, "flame": 0.25, "haze": 0.35},
    IncidentType.tornado: {"tornado": 0.15, "storm": 0.3, "thunderstorm": 0.3, "lightning": 0.3},
    IncidentType.severe_storm: {"storm": 0.3, "thunderstorm": 0.3, "lightning": 0.25, "tornado": 0.15},
    IncidentType.heavy_rain: {"storm": 0.3, "thunderstorm": 0.3, "water": 0.45, "water_body": 0.45},
    IncidentType.flood: {"water": 0.45, "water_body": 0.4, "waterways": 0.4},
    IncidentType.hurricane: {"storm": 0.3, "thunderstorm": 0.3, "water": 0.45, "ruins": 0.3},
    IncidentType.winter_storm: {"snow": 0.3, "blizzard": 0.2, "ice": 0.35},
    IncidentType.injury: {"ambulance": 0.3},
    IncidentType.other: {"ruins": 0.3},
}

# Scenes that are clearly indoors and calm.
INDOOR = {"interior_room": 0.4, "bedroom": 0.3, "living_room": 0.3, "kitchen_room": 0.3,
          "bathroom": 0.3, "bathroom_room": 0.3, "classroom": 0.3, "dining_room": 0.3, "office_supplies": 0.4}

# Fire labels that aren't emergencies.
CALM_FIRE = {"fireplace", "candle", "candlestick", "grill", "fireworks", "firecracker"}


def parse_labels(text: str) -> dict[str, float]:
    """'snow:0.82,blizzard:0.41' -> {"snow": 0.82, "blizzard": 0.41}"""
    labels = {}
    for part in (text or "").split(","):
        name, _, value = part.partition(":")
        try:
            labels[name.strip().lower()] = float(value)
        except ValueError:
            continue
    return labels


def scene_shows(labels: dict[str, float], rules: dict[str, float]) -> Optional[str]:
    """The first label that matches the rules, if any."""
    for name, minimum in rules.items():
        if labels.get(name, 0) >= minimum:
            return name
    return None


def confirms_report(media: Media, incident_type: IncidentType) -> Optional[bool]:
    """
    True if the photo shows what was reported, False if it clearly doesn't,
    and None if there's no way to tell (an old photo without scene labels,
    for a kind of report YOLO can't check).
    """
    labels = parse_labels(media.scene_labels)
    yolo_fire = media.fire_detected or media.smoke_detected
    indoor = scene_shows(labels, INDOOR) is not None
    calm_fire = any(labels.get(name, 0) >= 0.3 for name in CALM_FIRE)

    if incident_type in (IncidentType.fire, IncidentType.smoke):
        if calm_fire and not media.fire_detected:
            return False           # a fireplace or a grill
        if yolo_fire:
            return True
        return scene_shows(labels, SCENE_RULES[incident_type]) is not None if labels else False

    if incident_type == IncidentType.injury:
        # Someone has to be in the picture, and it can't be a calm room.
        if media.people_count == 0:
            return False
        return not indoor or scene_shows(labels, SCENE_RULES[incident_type]) is not None

    if not labels:
        return None                # nothing to check weather against
    if indoor and scene_shows(labels, SCENE_RULES[incident_type]) is None:
        return False
    return scene_shows(labels, SCENE_RULES[incident_type]) is not None


def explain(media: Media, incident_type: IncidentType) -> str:
    """A short, plain reason for the timeline."""
    result = confirms_report(media, incident_type)
    labels = parse_labels(media.scene_labels)
    if result:
        match = scene_shows(labels, SCENE_RULES[incident_type])
        if media.fire_detected or media.smoke_detected:
            return "Confirmed by the AI: it found fire or smoke in the photo. Now on the map."
        if match:
            return f"Confirmed by the AI: the photo shows {match.replace('_', ' ')}. Now on the map."
        return "Confirmed by the AI. Now on the map."
    what = {
        IncidentType.fire: "fire or smoke", IncidentType.smoke: "smoke", IncidentType.tornado: "a tornado or a storm",
        IncidentType.severe_storm: "a storm", IncidentType.heavy_rain: "heavy rain", IncidentType.flood: "flooding",
        IncidentType.hurricane: "a hurricane", IncidentType.winter_storm: "snow or ice",
        IncidentType.injury: "anyone hurt", IncidentType.other: "an emergency",
    }[incident_type]
    where = " It looks like it was taken indoors." if scene_shows(labels, INDOOR) else ""
    return (f"The AI couldn't see {what} in the photo, so it isn't on the map.{where} "
            "A first responder will review it.")
