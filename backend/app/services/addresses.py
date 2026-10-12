"""
Comparing addresses typed by different people.

"1418 Lee Street" and "1418  lee st." are the same place, so before comparing
we lowercase, drop punctuation and extra spaces, and shorten common words
(street -> st, drive -> dr, ...).
"""

import re

SHORT_FORMS = {
    "street": "st", "drive": "dr", "road": "rd", "lane": "ln", "court": "ct",
    "avenue": "ave", "boulevard": "blvd", "trail": "trl", "circle": "cir",
    "place": "pl", "parkway": "pkwy", "highway": "hwy", "north": "n",
    "south": "s", "east": "e", "west": "w",
}


def normalize(address: str) -> str:
    words = re.sub(r"[^a-z0-9 ]", " ", address.lower()).split()
    return " ".join(SHORT_FORMS.get(word, word) for word in words)
