"""
Fill the database with fictional demo households and volunteer buddies
around North Texas. (Every person, street and phone number is made up; see
demo_data.py.)

Run from the backend folder:
    python -m scripts.seed          (only works on an empty database)
    python -m scripts.reset_demo    (wipe everything, then seed again)
"""

import math
import random
import sys

from sqlmodel import Session, select

from app.config import BUDDY_MAX_DISTANCE_KM
from app.database import create_tables, engine
from app.models import BuddyLink, Household, Language, TimelineKind, Volunteer
from app.services.geo import distance_km
from app.services.timeline import add_event
from scripts.demo_data import FIRST_NAMES, LAST_NAMES, SPANISH_FIRST, SPANISH_LAST, STREETS, TOWNS, VOLUNTEERS

# A fixed random seed: the "random" demo data comes out the same every time.
rng = random.Random(4)
_phone = iter(range(100, 200))


def fake_phone() -> str:
    """(903) 555-01xx: numbers reserved for fiction, so no real person is ever dialed."""
    return f"(903) 555-0{next(_phone):03d}"[:14]


def scatter(center: tuple[float, float], max_km: float) -> tuple[float, float]:
    """A random point within max_km of a town center."""
    angle = rng.uniform(0, 2 * math.pi)
    dist = max_km * math.sqrt(rng.random())
    lat = center[0] + (dist / 111.32) * math.cos(angle)
    lon = center[1] + (dist / (111.32 * math.cos(math.radians(center[0])))) * math.sin(angle)
    return round(lat, 6), round(lon, 6)


def make_household(town: str, center: tuple[float, float], spanish: bool) -> Household:
    first = rng.choice([n for i, n in enumerate(FIRST_NAMES) if (i in SPANISH_FIRST) == spanish])
    last = rng.choice([n for i, n in enumerate(LAST_NAMES) if (i in SPANISH_LAST) == spanish])
    lat, lon = scatter(center, 3.0 if town == "Greenville" else 2.5)

    # A realistic mix of household types.
    kind = rng.choices(["senior_alone", "senior_couple", "family", "adult_alone", "adults"],
                       weights=[25, 15, 30, 15, 15])[0]
    seniors = {"senior_alone": 1, "senior_couple": 2}.get(kind, 1 if rng.random() < 0.15 else 0)
    adults = {"family": rng.randint(1, 2), "adult_alone": 1, "adults": rng.randint(2, 3)}.get(kind, 0)
    children = rng.randint(1, 4) if kind == "family" else 0

    equipment = []
    if rng.random() < (0.35 if seniors else 0.08):
        equipment = rng.sample(["oxygen", "cpap", "dialysis", "power_wheelchair"], k=rng.choice([1, 1, 2]))

    rural = rng.random() < 0.3
    contact_first = rng.choice(FIRST_NAMES)
    return Household(
        contact_name=f"{first} {last}",
        phone=fake_phone(),
        address=f"{rng.randint(100, 9899)} {rng.choice(STREETS)}",
        city=town,
        latitude=lat,
        longitude=lon,
        children=children,
        adults=adults,
        seniors=seniors,
        mobility_needs=rng.random() < (0.35 if seniors else 0.06),
        medical_equipment=",".join(sorted(equipment)),
        no_vehicle=rng.random() < (0.3 if seniors else 0.1),
        pets=rng.random() < 0.55,
        livestock=rural and rng.random() < 0.5,
        language=Language.es if spanish else Language.en,
        notes="",
        emergency_contact_name=f"{contact_first} {last}",
        emergency_contact_phone=fake_phone(),
        wants_buddy=bool(seniors or equipment) and rng.random() < 0.75 or rng.random() < 0.1,
        is_demo=True,
    )


def match_buddies(session: Session, households: list[Household], volunteers: list[Volunteer]) -> None:
    """Give each household that asked for a buddy the nearest volunteer who still has room."""
    load = {v.id: 0 for v in volunteers}
    for h in households:
        if not h.wants_buddy:
            continue
        options = sorted(
            (distance_km(h.latitude, h.longitude, v.latitude, v.longitude), v) for v in volunteers
            if load[v.id] < v.capacity
        )
        if options and options[0][0] <= BUDDY_MAX_DISTANCE_KM:
            volunteer = options[0][1]
            load[volunteer.id] += 1
            session.add(BuddyLink(volunteer_id=volunteer.id, household_id=h.id))
            add_event(session, h.id, TimelineKind.buddy, f"{volunteer.name} agreed to check on this household")


def seed() -> None:
    create_tables()
    with Session(engine) as session:
        if session.exec(select(Household)).first() is not None:
            sys.exit("The database already has households. Run `python -m scripts.reset_demo` to start over.")

        households = []
        for town, (center, count) in TOWNS.items():
            for _ in range(count):
                household = make_household(town, center, spanish=rng.random() < 0.25)
                session.add(household)
                households.append(household)
        volunteers = []
        for name, town, capacity in VOLUNTEERS:
            lat, lon = scatter(TOWNS[town][0], 2.0)
            volunteer = Volunteer(name=name, phone=fake_phone(), city=town, latitude=lat, longitude=lon,
                                  capacity=capacity, is_demo=True)
            session.add(volunteer)
            volunteers.append(volunteer)
        session.flush()
        for h in households:
            add_event(session, h.id, TimelineKind.profile, "Household registered with RollCall")
        match_buddies(session, households, volunteers)
        session.commit()

        print(f"Created {len(households)} fictional households and {len(volunteers)} volunteer buddies.")
        print_summary(households)


def print_summary(households: list[Household]) -> None:
    def share(test):
        return sum(1 for h in households if test(h))
    print(f"  65+ living alone ........ {share(lambda h: h.lives_alone and h.seniors)}")
    print(f"  powered medical equipment {share(lambda h: h.medical_equipment)}")
    print(f"  no vehicle .............. {share(lambda h: h.no_vehicle)}")
    print(f"  mobility needs .......... {share(lambda h: h.mobility_needs)}")
    print(f"  children ................ {share(lambda h: h.children)}")
    print(f"  Spanish-speaking ........ {share(lambda h: h.language == Language.es)}")
    print(f"  asked for a buddy ....... {share(lambda h: h.wants_buddy)}")


if __name__ == "__main__":
    seed()
