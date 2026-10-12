"""
Fill the database with the demo data:
  - incidents with photos/videos checked by the AI (seed_incidents.py), and
  - fictional demo accounts: households, volunteer buddies, a responder, and
    neighborhood communities around North Texas (below). Every person,
    neighborhood, street and phone number is made up; see demo_data.py.

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
from app.models import (
    BuddyLink,
    BuddyStatus,
    Community,
    CommunityMember,
    Household,
    Language,
    MemberStatus,
    TimelineKind,
    User,
    Volunteer,
)
from app.services.geo import distance_km
from app.services.timeline import add_household_event
from scripts.seed_incidents import seed_incidents
from scripts.demo_data import (
    COMMUNITIES,
    FIRST_NAMES,
    LAST_NAMES,
    RESPONDER_EMAIL,
    RESPONDER_NAME,
    SPANISH_FIRST,
    SPANISH_LAST,
    STREETS,
    TOWNS,
    VOLUNTEER_COMMUNITY,
    VOLUNTEERS,
    ZIP_CODES,
)

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


def demo_user(session: Session, name: str, used_emails: set[str], **fields) -> User:
    """A fictional account. Its email uses example.com (reserved for examples),
    and it has no usable password: it can only be opened from the demo list."""
    base = name.lower().replace(" ", ".").replace("á", "a").replace("é", "e").replace("í", "i") \
        .replace("ó", "o").replace("ú", "u").replace("ñ", "n")
    email, n = f"{base}@example.com", 2
    while email in used_emails:
        email, n = f"{base}{n}@example.com", n + 1
    used_emails.add(email)
    user = User(name=name, email=email, password_hash="demo-account", is_demo=True, **fields)
    session.add(user)
    session.flush()
    return user


def link(session: Session, volunteer: Volunteer, volunteer_name: str, household: Household,
         typed: bool, active: bool) -> None:
    """Record that a volunteer asked to check on a household (and maybe was accepted)."""
    session.add(BuddyLink(
        volunteer_id=volunteer.id, household_id=household.id,
        typed_address=f"{household.address}, {household.city} {household.zip_code}" if typed else "",
        status=BuddyStatus.active if active else BuddyStatus.pending,
    ))
    if active:
        add_household_event(session, household.id, TimelineKind.buddy, f"{volunteer_name} is now this household's buddy")


def match_buddies(session: Session, households: list[Household], volunteers: list[tuple[Volunteer, User]],
                  community_of_user: dict[int, str]) -> None:
    """
    Give each household that asked for a buddy a volunteer, following the
    community rules: neighbors in the same community first; otherwise the
    nearest volunteer (who "typed the address"), if the household's community
    allows outside buddies. Every 5th match is left as a request the resident
    still has to accept, so the demo shows both.
    """
    load = {v.id: 0 for v, _ in volunteers}
    outside_ok = {name: allowed for name, _, allowed in COMMUNITIES}
    matches = 0
    for h in households:
        if not h.wants_buddy:
            continue
        mine = community_of_user.get(h.owner_id)
        same = [(v, u) for v, u in volunteers if mine and community_of_user.get(u.id) == mine and load[v.id] < v.capacity]
        typed = not same
        if typed:
            if mine and not outside_ok[mine]:
                continue
            center = TOWNS[h.city][0]
            same = sorted(
                ((v, u) for v, u in volunteers if load[v.id] < v.capacity
                 and distance_km(*center, *TOWNS[v.city][0]) <= BUDDY_MAX_DISTANCE_KM),
                key=lambda pair: distance_km(*center, *TOWNS[pair[0].city][0]),
            )
        if not same:
            continue
        volunteer, volunteer_user = same[0]
        matches += 1
        active = matches % 5 != 0
        if active:
            load[volunteer.id] += 1
        link(session, volunteer, volunteer_user.name, h, typed=typed, active=active)


def add_demo_story(session: Session, community: Community, households: list[Household],
                   volunteers: list[tuple[Volunteer, User]]) -> Household:
    """
    The featured demo resident (Pecan Hollow's admin) asked for a buddy, and a
    neighbor has offered, so the demo can show a resident accepting. (They also
    have a neighbor waiting to join their community, from the memberships above.)
    Returns their household, which automatic matching then leaves alone.
    """
    home = next(h for h in households if h.owner_id == community.created_by)
    neighbor, _ = next((v, u) for v, u in volunteers if VOLUNTEER_COMMUNITY.get(u.name) == community.name)
    home.wants_buddy = True
    session.add(home)
    session.add(BuddyLink(volunteer_id=neighbor.id, household_id=home.id, status=BuddyStatus.pending))
    return home


def seed() -> None:
    """Everything: incidents for the Map/Incidents tabs, households for Roll Call."""
    seed_incidents()
    print()
    seed_households()


def seed_households() -> None:
    # Start the "random" choices and phone numbers over, so the demo data is
    # exactly the same every time (even if this runs twice, as in the tests).
    global rng, _phone
    rng, _phone = random.Random(4), iter(range(100, 200))
    create_tables()
    with Session(engine) as session:
        if session.exec(select(Household)).first() is not None:
            sys.exit("The database already has households. Run `python -m scripts.reset_demo` to start over.")
        emails: set[str] = set()

        # Communities are created first; their admin is set once members exist.
        communities = {}
        for name, town, allowed in COMMUNITIES:
            communities[name] = Community(name=name, city=town, allow_outside_buddies=allowed, created_by=0, is_demo=True)

        # Households, each owned by a fictional account.
        households = []
        town_communities = {town: [n for n, t, _ in COMMUNITIES if t == town] for town in TOWNS}
        memberships: list[tuple[int, str]] = []   # (user id, community name) in joining order
        for town, (center, count) in TOWNS.items():
            for i in range(count):
                household = make_household(town, center, spanish=rng.random() < 0.25)
                owner = demo_user(session, household.contact_name, emails)
                household.owner_id = owner.id
                household.zip_code = ZIP_CODES[town]
                session.add(household)
                households.append(household)
                options = town_communities[town]
                if options:
                    memberships.append((owner.id, options[i % len(options)]))

        # Volunteers.
        volunteers = []
        for name, town, capacity in VOLUNTEERS:
            user = demo_user(session, name, emails)
            volunteer = Volunteer(user_id=user.id, phone=fake_phone(), city=town, capacity=capacity)
            session.add(volunteer)
            volunteers.append((volunteer, user))
            if name in VOLUNTEER_COMMUNITY:
                memberships.append((user.id, VOLUNTEER_COMMUNITY[name]))

        # A responder.
        responder = User(name=RESPONDER_NAME, email=RESPONDER_EMAIL, password_hash="demo-account",
                         is_responder=True, is_demo=True)
        session.add(responder)
        session.flush()

        # Community memberships: the first member of each becomes its admin, and
        # the last household to ask in each Greenville community is still waiting
        # for the admin to approve.
        for c in communities.values():
            session.add(c)
        session.flush()
        last_household_member = {}
        for user_id, cname in memberships:
            if any(h.owner_id == user_id for h in households):
                last_household_member[cname] = user_id
        community_of_user: dict[int, str] = {}
        for user_id, cname in memberships:
            community = communities[cname]
            first = community.created_by == 0
            if first:
                community.created_by = user_id
                session.add(community)
            pending = community.city == "Greenville" and last_household_member.get(cname) == user_id
            session.add(CommunityMember(community_id=community.id, user_id=user_id, is_admin=first,
                                        status=MemberStatus.pending if pending else MemberStatus.member))
            if not pending:
                community_of_user[user_id] = cname
        session.flush()

        for h in households:
            add_household_event(session, h.id, TimelineKind.profile, "Household joined the roll call")
        story_home = add_demo_story(session, communities["Pecan Hollow"], households, volunteers)
        match_buddies(session, [h for h in households if h is not story_home], volunteers, community_of_user)
        session.commit()

        print(f"Created {len(households)} fictional households, {len(volunteers)} volunteer buddies, "
              f"{len(communities)} communities and 1 responder (all demo accounts).")
        print_summary(households)
        links = session.exec(select(BuddyLink)).all()
        print(f"  buddy matches ........... {sum(l.status == BuddyStatus.active for l in links)} "
              f"(+{sum(l.status == BuddyStatus.pending for l in links)} waiting for the resident)")


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
