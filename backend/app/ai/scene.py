"""
Who might need help? Simple, explainable rules on top of YOLO's person boxes.

  * "May be down": a person whose box is clearly wider than it is tall is
    probably lying on the ground (people standing or walking are tall and
    narrow). Someone lying near a fire or in a crash could be injured.
  * "Near the flames": a person whose box touches the area around a fire box.

These are hints for responders, not diagnoses. Someone lying down might just
be resting, and a camera angle can make distances look shorter than they are.
"""

from app.ai.detections import Detection

DOWN_MIN_WIDTH_TO_HEIGHT = 1.3   # box at least 1.3x wider than tall
DOWN_MIN_CONFIDENCE = 0.45       # only trust fairly clear detections
NEAR_FIRE_MARGIN = 0.5           # grow each person's box by half its height


def _overlaps(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def is_down(person: Detection) -> bool:
    x1, y1, x2, y2 = person.box
    width, height = x2 - x1, max(y2 - y1, 1)
    return person.confidence >= DOWN_MIN_CONFIDENCE and width / height >= DOWN_MIN_WIDTH_TO_HEIGHT


def is_near_fire(person: Detection, fire_boxes: list[Detection]) -> bool:
    x1, y1, x2, y2 = person.box
    margin = int((y2 - y1) * NEAR_FIRE_MARGIN)
    grown = (x1 - margin, y1 - margin, x2 + margin, y2 + margin)
    return any(_overlaps(grown, fire.box) for fire in fire_boxes)


def label_people(people: list[Detection], fire_boxes: list[Detection]) -> tuple[list[Detection], int, int]:
    """
    Returns (people with clearer labels for the picture, how many may be down,
    how many are near the flames).
    """
    labeled, down, near = [], 0, 0
    for person in people:
        if is_down(person):
            down += 1
            labeled.append(Detection("person down?", person.confidence, person.box))
        elif is_near_fire(person, fire_boxes):
            near += 1
            labeled.append(Detection("person near fire", person.confidence, person.box))
        else:
            labeled.append(person)
    return labeled, down, near
