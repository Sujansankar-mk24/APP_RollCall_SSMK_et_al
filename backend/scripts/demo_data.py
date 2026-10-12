"""
Fictional demo people and places for RollCall.

Everything here is MADE UP:
  * names are invented combinations,
  * street names are invented (no real roads are used),
  * phone numbers use 555-0100 to 555-0199, the range reserved for fiction.
Only the towns and their rough center points are real, so the map shows
households in believable places around North Texas.
"""

# Town -> (latitude, longitude) of roughly the town center, and how many
# demo households to place around it. Greenville gets the most, because the
# scripted tornado-warning demo happens there.
TOWNS = {
    "Greenville": ((33.1385, -96.1108), 12),
    "Caddo Mills": ((33.0657, -96.2275), 3),
    "Commerce": ((33.2468, -95.9000), 4),
    "Royse City": ((32.9751, -96.3325), 3),
    "Farmersville": ((33.1631, -96.3597), 3),
    "Wolfe City": ((33.3707, -96.0697), 2),
    "Leonard": ((33.3790, -96.2475), 2),
    "Bonham": ((33.5776, -96.1786), 3),
    "Sherman": ((33.6357, -96.6089), 3),
    "Paris": ((33.6609, -95.5555), 3),
    "Sulphur Springs": ((33.1385, -95.6011), 2),
}

STREETS = [
    "Pecan Hollow Dr", "Bluebonnet Ridge Ln", "Cedar Bend Rd", "Mesquite Trail", "Prairie Wind Dr",
    "Old Mill Creek Rd", "Live Oak Bend", "Sagebrush Ct", "Cottonwood Crossing", "Meadowlark Ln",
    "Juniper Hollow", "Windmill Ridge Rd", "Lantana Way", "Sweetgum St", "Quail Run Dr",
    "Pine Needle Ct", "Harvest Moon Rd", "Wildflower Path", "Stonebridge Ln", "Red Cardinal Dr",
    "Possum Trot Rd", "Bois d'Arc Bend", "Indian Paintbrush Ln", "Sorghum Field Rd", "Hackberry Hollow",
]

FIRST_NAMES = [
    "Margaret", "Harold", "Dorothy", "Walter", "Betty", "Eugene", "Lorraine", "Clarence", "Ruth", "Earl",
    "Jasmine", "Marcus", "Tiffany", "Derrick", "Ashley", "Brandon", "Kayla", "Tyler", "Brittany", "Jordan",
    "María", "José", "Guadalupe", "Juan", "Rosa", "Luis", "Carmen", "Miguel", "Esperanza", "Alejandro",
    "Nguyen", "Priya", "Hassan", "Mei", "Samuel", "Grace", "Benjamin", "Hannah", "Isaiah", "Naomi",
]
LAST_NAMES = [
    "Ellis", "Whitfield", "Pruitt", "Gaines", "Holloway", "McBride", "Tatum", "Crawford", "Dunlap", "Ferrell",
    "Garza", "Hernández", "Villarreal", "Castillo", "Treviño", "Salazar", "Ochoa", "Mendoza", "Ybarra", "Cantú",
    "Washington", "Freeman", "Okafor", "Tran", "Patel", "Haddad", "Lindqvist", "Yazzie", "Boone", "Carver",
]

# Spanish-speaking households use names from this set (indices into FIRST/LAST).
SPANISH_FIRST = set(range(20, 30))
SPANISH_LAST = set(range(10, 20))

VOLUNTEERS = [
    ("Daniel Okafor", "Greenville", 6),
    ("Rachel Whitfield", "Greenville", 5),
    ("Luis Treviño", "Greenville", 5),
    ("Megan Holloway", "Royse City", 4),
    ("Caleb Freeman", "Commerce", 4),
    ("Ana Villarreal", "Sherman", 4),
    ("Grant Pruitt", "Paris", 4),
    ("Hope Lindqvist", "Bonham", 4),
]

# ZIP code for each town (real ZIP codes, so typed addresses look normal;
# the street names and house numbers are still made up).
ZIP_CODES = {
    "Greenville": "75401", "Caddo Mills": "75135", "Commerce": "75428", "Royse City": "75189",
    "Farmersville": "75442", "Wolfe City": "75496", "Leonard": "75452", "Bonham": "75418",
    "Sherman": "75090", "Paris": "75460", "Sulphur Springs": "75482",
}

# Fictional neighborhoods (named after the made-up streets above):
# (name, town, allows buddies from outside the community?)
COMMUNITIES = [
    ("Pecan Hollow", "Greenville", False),
    ("Bluebonnet Ridge", "Greenville", True),
    ("Cottonwood Crossing", "Commerce", False),
    ("Prairie Wind", "Royse City", False),
]

# Which community each demo volunteer belongs to (None = no community).
VOLUNTEER_COMMUNITY = {
    "Daniel Okafor": "Pecan Hollow",
    "Luis Treviño": "Pecan Hollow",
    "Rachel Whitfield": "Bluebonnet Ridge",
    "Caleb Freeman": "Cottonwood Crossing",
    "Megan Holloway": "Prairie Wind",
}

# A fictional responder account. In real life, the county would issue these.
RESPONDER_NAME = "Alex Rivera"
RESPONDER_EMAIL = "responder@example.com"
