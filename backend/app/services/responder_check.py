"""
The automatic check on a first responder application, done before a person
reviews it (python -m scripts.review_responders shows the result).

Two kinds of checks:

1. The ID photo. The iPhone reads the words on the ID with Apple's Vision
   framework (on the phone) and sends them along. Here they're compared with
   what the applicant typed:
       - their name is on the ID
       - the agency's name is on the ID
       - the badge number is on the ID
       - it looks like a responder ID (words like Fire, Police, Sheriff, EMS)
2. The internet. Is the agency real? It's looked up on Wikipedia (big
   departments have articles) and in OpenStreetMap, which maps fire
   stations, police stations and EMS stations with their names (so a small
   town's fire department shows up as its stations). Both are free and need
   no key.

What it can't do: badge numbers and employee lists aren't public, so nothing
online can prove that this person works there. Someone could also make a fake
card with matching words. That's why a person still makes the final decision,
and the check is shown to them as a recommendation.
"""

import json
import re
from typing import Optional

import httpx
from sqlmodel import Session

from app.config import DATA_USER_AGENT
from app.models import User

RESPONDER_WORDS = ("fire", "police", "sheriff", "ems", "rescue", "paramedic", "emt", "firefighter", "officer",
                   "department", "dept", "constable", "marshal", "trooper", "public safety", "emergency", "badge")

# Words too common to count when matching an agency's name ("Greenville Fire Department").
COMMON_WORDS = {"the", "of", "and", "department", "dept", "county", "city", "services", "service", "office", "texas"}

# OpenStreetMap places that count as a real agency.
AGENCY_PLACES = {"fire_station", "police", "ambulance_station", "rescue_station", "townhall", "courthouse"}


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def check_id_text(id_text: str, name: str, agency: str, badge: str) -> dict[str, bool]:
    """Compare the words read on the ID with what the applicant typed."""
    found = set(words(id_text))
    flat = " ".join(words(id_text))
    name_parts = [w for w in words(name) if len(w) > 1]
    agency_parts = [w for w in words(agency) if w not in COMMON_WORDS and len(w) > 2]
    badge_digits = "".join(words(badge))
    return {
        "read_text": len(flat) >= 10,
        # The last name is enough (IDs often show "J. Smith").
        "name_on_id": bool(name_parts) and name_parts[-1] in found,
        # At least half of the agency's distinctive words.
        "agency_on_id": bool(agency_parts) and sum(w in found for w in agency_parts) * 2 >= len(agency_parts),
        "badge_on_id": len(badge_digits) >= 2 and badge_digits in flat.replace(" ", ""),
        "looks_like_responder_id": any(w in flat for w in RESPONDER_WORDS),
    }


# What kind of place to look for on the map, by the words in the agency's name.
PLACE_KINDS = (("fire", "fire station"), ("rescue", "fire station"), ("police", "police"),
               ("sheriff", "sheriff"), ("ems", "ambulance station"), ("ambulance", "ambulance station"),
               ("constable", "police"), ("marshal", "police"))


def lookup_agency_online(agency: str, city: str) -> Optional[str]:
    """
    Search the internet for the agency. Returns what was found (for example
    "Greenville Fire Station #1 (OpenStreetMap)"), or None if nothing matched.
    Raises httpx.HTTPError if the internet can't be reached.
    """
    agency_words = set(words(agency))
    distinctive = [w for w in agency_words if w not in COMMON_WORDS and len(w) > 2]
    city_words = set(words(city))
    with httpx.Client(timeout=10, headers={"User-Agent": DATA_USER_AGENT}) as client:
        # 1. Wikipedia: an article about the agency, e.g. "Dallas Police Department".
        response = client.get("https://en.wikipedia.org/w/api.php", params={
            "action": "query", "list": "search", "srsearch": agency, "format": "json", "srlimit": 5})
        response.raise_for_status()
        for result in response.json().get("query", {}).get("search", []):
            title = set(words(result.get("title", "")))
            if distinctive and all(w in title for w in distinctive):
                return f"{result['title']} (Wikipedia)"
        # 2. OpenStreetMap: a fire station, police station or EMS station of
        #    that kind, in that town, named after the town or the agency.
        kind = next((place for word, place in PLACE_KINDS if word in agency_words), None)
        if kind is None:
            return None
        response = client.get("https://nominatim.openstreetmap.org/search", params={
            "q": f"{kind}, {city}, Texas", "format": "jsonv2", "limit": 10, "countrycodes": "us"})
        response.raise_for_status()
        for place in response.json():
            name = set(words(place.get("name") or ""))
            if place.get("type") in AGENCY_PLACES and (name & city_words or name & set(distinctive)):
                return f"{place['name']} in {city} (OpenStreetMap)"
    return None


def verdict(checks: dict[str, bool], online: Optional[str], online_checked: bool) -> str:
    """One line for the reviewer: looks real, check closely, or doesn't match."""
    if not checks["read_text"]:
        return "No text could be read on the ID photo. Look at it closely."
    matched = sum(checks[k] for k in ("name_on_id", "agency_on_id", "badge_on_id", "looks_like_responder_id"))
    if matched >= 3 and checks["name_on_id"] and (online or not online_checked):
        return "Looks real: the ID matches what they typed" + (" and the agency exists." if online else ".")
    if matched >= 3 and checks["name_on_id"]:
        return "Check closely: the ID matches what they typed, but the agency wasn't found online."
    if matched <= 1:
        return "Doesn't match: the ID doesn't show what they typed."
    return "Check closely: only part of the ID matches what they typed."


def run_check(user: User, id_text: str) -> dict:
    """Everything the reviewer sees, as a dictionary (saved as JSON on the account)."""
    checks = check_id_text(id_text, user.name, user.responder_agency, user.responder_badge)
    online, online_checked = None, True
    try:
        online = lookup_agency_online(user.responder_agency, user.responder_city)
    except (httpx.HTTPError, ValueError):
        online_checked = False   # no internet: the reviewer is told it wasn't checked
    return {
        "verdict": verdict(checks, online, online_checked),
        "checks": checks,
        "agency_found_online": online,
        "online_checked": online_checked,
    }


def check_application(session: Session, user_id: int, id_text: str) -> None:
    """Run the check and save it on the account (runs in the background)."""
    user = session.get(User, user_id)
    if user is None:
        return
    user.responder_check = json.dumps(run_check(user, id_text))
    session.add(user)
    session.commit()
