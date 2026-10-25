"""Does a report's photo show the disaster that was reported? (app/ai/verify.py)"""

from app.ai.fire import BASIC_DETECTOR_NAME
from app.ai.verify import confirms_report
from app.models import AnalysisStatus, IncidentType, Media, MediaKind


def photo(**ai) -> Media:
    return Media(incident_id=1, kind=MediaKind.photo, file_name="x.jpg", analysis_status=AnalysisStatus.done, **ai)


def test_the_color_rule_alone_never_confirms_a_fire():
    # A selfie in an orange shirt: the basic color rule "sees" flames, the phone sees a person.
    selfie = photo(fire_detected=True, fire_confidence=0.6, people_count=1, fire_detector=BASIC_DETECTOR_NAME,
                   scene_labels="people:0.8,adult:0.7,clothing:0.4")
    assert confirms_report(selfie, IncidentType.fire) is False
    # With no scene labels at all, it still isn't enough.
    assert confirms_report(photo(fire_detected=True, fire_detector=BASIC_DETECTOR_NAME), IncidentType.fire) is False
    # When the phone also sees fire, it counts.
    real = photo(fire_detected=True, fire_detector=BASIC_DETECTOR_NAME, scene_labels="fire:0.7,smoke:0.4")
    assert confirms_report(real, IncidentType.fire) is True


def test_the_trained_model_needs_backup_indoors():
    unsure_indoors = photo(fire_detected=True, fire_confidence=0.5, fire_detector="fire.pt",
                           scene_labels="interior_room:0.8,people:0.6")
    assert confirms_report(unsure_indoors, IncidentType.fire) is False
    sure = photo(fire_detected=True, fire_confidence=0.85, fire_detector="fire.pt")
    assert confirms_report(sure, IncidentType.fire) is True
    outdoors = photo(fire_detected=True, fire_confidence=0.5, fire_detector="fire.pt", scene_labels="grass:0.6")
    assert confirms_report(outdoors, IncidentType.fire) is True


def test_people_are_never_enough_for_a_fire():
    group = photo(people_count=5, scene_labels="people:0.72,adult:0.70")
    assert confirms_report(group, IncidentType.fire) is False
