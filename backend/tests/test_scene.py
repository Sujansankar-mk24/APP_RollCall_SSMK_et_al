"""Tests for the "who might need help?" rules (app/ai/scene.py)."""

from app.ai.detections import Detection
from app.ai.scene import is_down, is_near_fire, label_people

STANDING = Detection("person", 0.9, (100, 100, 140, 220))  # tall and narrow
LYING = Detection("person", 0.9, (100, 200, 260, 250))     # wide and short
FIRE = Detection("fire", 0.8, (180, 100, 300, 220))


def test_lying_person_may_be_down():
    assert is_down(LYING)
    assert not is_down(STANDING)


def test_unclear_detections_are_not_called_down():
    assert not is_down(Detection("person", 0.3, LYING.box))


def test_person_next_to_fire_is_near_the_flames():
    assert is_near_fire(STANDING, [FIRE])
    far_away = Detection("person", 0.9, (600, 100, 640, 220))
    assert not is_near_fire(far_away, [FIRE])


def test_label_people_counts_and_relabels():
    labeled, down, near = label_people([STANDING, LYING], [FIRE])
    assert (down, near) == (1, 1)
    assert {d.label for d in labeled} == {"person down?", "person near fire"}
