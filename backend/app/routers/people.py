"""
Profiles and first responders:

  PATCH  /me/profile                   your name, bio, phone, "away from home"
  PUT    /me/photo                     your profile picture (a photo upload)
  DELETE /me/photo                     remove it
  GET    /people/{user_id}             someone's profile (see app/services/people.py
                                       for who can see what)
  POST   /me/responder-application     apply as a first responder: agency, role,
                                       badge number, area, and a photo of your ID
  GET    /responders?city=Greenville   verified first responders (in an area)
  POST   /responders/{user_id}/report  flag a responder as fake, abusive or reckless

First responder applications are reviewed by a person (the app's admin) with
python -m scripts.review_responders. There's no government database to check
IDs against, so a human looks at each one. The ID photo is kept out of
media/ (never shared) and deleted right after the review.
"""

from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlmodel import Session, func, select

from app.auth import current_user
from app.config import ID_PHOTOS_DIR, MAX_TEXT_LENGTH
from app.database import get_session
from app.models import ResponderReport, ResponderStatus, User
from app.schemas import MeOut, PersonOut, ProfilePatch, ResponderReportIn
from app.services.accounts import me_out
from app.services.people import (can_view_person, delete_media, is_verified_responder, person_out,
                                 save_picture, save_profile_picture)

router = APIRouter(tags=["people"])


@router.patch("/me/profile", response_model=MeOut)
def update_profile(data: ProfilePatch, user: User = Depends(current_user), session: Session = Depends(get_session)):
    if data.name is not None:
        user.name = data.name.strip()
    if data.bio is not None:
        user.bio = data.bio.strip()
    if data.phone is not None:
        user.phone = data.phone.strip()
    if data.away_from_home is not None:
        user.away_from_home = data.away_from_home
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.put("/me/photo", response_model=MeOut)
async def set_photo(file: UploadFile = File(...), user: User = Depends(current_user),
                    session: Session = Depends(get_session)):
    new_name = await save_profile_picture(file)
    delete_media(user.photo_path)
    user.photo_path = new_name
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.delete("/me/photo", response_model=MeOut)
def remove_photo(user: User = Depends(current_user), session: Session = Depends(get_session)):
    delete_media(user.photo_path)
    user.photo_path = None
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.get("/people/{user_id}", response_model=PersonOut)
def person(user_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    other = session.get(User, user_id)
    # The same answer for "no such person" and "not shared with you", so this
    # can't be used to find out who has an account.
    if other is None or not can_view_person(session, user, other):
        raise HTTPException(status_code=404, detail="This profile isn't shared with you.")
    return person_out(session, user, other)


# ---------------------------------------------------------------------------
# First responders
# ---------------------------------------------------------------------------

@router.post("/me/responder-application", response_model=MeOut)
async def apply_as_responder(
    agency: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    role: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    badge_number: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    city: str = Form(..., min_length=2, max_length=MAX_TEXT_LENGTH),
    id_photo: UploadFile = File(...),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    if is_verified_responder(user):
        raise HTTPException(status_code=400, detail="You're already a verified first responder.")
    saved = await save_picture(id_photo, ID_PHOTOS_DIR)
    if user.responder_id_photo:
        (ID_PHOTOS_DIR / user.responder_id_photo).unlink(missing_ok=True)   # replace an older application
    user.responder_status = ResponderStatus.pending
    user.responder_agency, user.responder_role = agency.strip(), role.strip()
    user.responder_badge, user.responder_city = badge_number.strip(), city.strip()
    user.responder_id_photo = saved.name
    session.add(user)
    session.commit()
    return me_out(session, user)


@router.get("/responders", response_model=list[PersonOut])
def responders(city: Optional[str] = None, user: User = Depends(current_user),
               session: Session = Depends(get_session)):
    query = select(User).where(User.is_responder == True)  # noqa: E712 (SQL needs ==)
    if city:
        query = query.where(func.lower(User.responder_city) == city.strip().lower())
    people = [p for p in session.exec(query.order_by(User.name)).all() if is_verified_responder(p)]
    return [person_out(session, user, p) for p in people]


@router.post("/responders/{responder_id}/report", status_code=201)
def report_responder(responder_id: int, data: ResponderReportIn, user: User = Depends(current_user),
                     session: Session = Depends(get_session)):
    responder = session.get(User, responder_id)
    if responder is None or not is_verified_responder(responder):
        raise HTTPException(status_code=404, detail="First responder not found.")
    if responder.id == user.id:
        raise HTTPException(status_code=400, detail="You can't report yourself.")
    session.add(ResponderReport(responder_id=responder.id, reporter_id=user.id,
                                reason=data.reason, details=data.details.strip()))
    session.commit()
    return {"message": "Thanks. Your report will be reviewed. It isn't shared with the responder."}
