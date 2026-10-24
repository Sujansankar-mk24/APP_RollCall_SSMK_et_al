"""
Community (neighborhood) endpoints:

  GET    /communities?q=pecan                 search by name
  POST   /communities                         create one; you become its admin
  GET    /communities/{id}                    details (members only for members,
                                              join requests only for admins)
  POST   /communities/{id}/join               ask to join
  POST   /communities/{id}/leave              leave (or cancel your request)
  POST   /communities/{id}/requests/{user}/approve   admin: let someone in
  POST   /communities/{id}/requests/{user}/decline   admin: say no
  PATCH  /communities/{id}                    admin: rename it
  PUT    /communities/{id}/photo              admin: the community's picture

Weekly Recap (photos from the neighborhood, like a shared photo roll):
  POST   /communities/{id}/recap              a member adds a photo (the admin approves it)
  POST   /communities/{id}/recap/{photo}/approve    admin
  POST   /communities/{id}/recap/{photo}/reject     admin
  POST   /communities/{id}/recap/{photo}/pin        admin: keep it past the week
  POST   /communities/{id}/recap/{photo}/unpin      admin
  DELETE /communities/{id}/recap/{photo}            admin, or whoever added it

Each person belongs to (or is asking to join) one community at a time.
Anyone signed in can open any community and see its Weekly Recap. Only
members see who's in it.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from sqlmodel import Session, delete, func, select

from app.auth import current_user
from app.config import PROFILES_DIR, RECAP_DAYS
from app.database import get_session
from app.models import Community, CommunityMember, CommunityPhoto, MemberStatus, PhotoStatus, User
from app.privacy import membership, volunteer_of
from app.schemas import CommunityDetailOut, CommunityIn, CommunityOut, CommunityPatch, MemberOut, RecapPhotoOut
from app.services.households import utc
from app.services.incident_views import media_url
from app.services.people import delete_media, has_active_buddy, household_of, media_name, save_picture

router = APIRouter(prefix="/communities", tags=["communities"])


def get_or_404(session: Session, community_id: int) -> Community:
    community = session.get(Community, community_id)
    if community is None:
        raise HTTPException(status_code=404, detail="Community not found")
    return community


def member_count(session: Session, community_id: int) -> int:
    return session.exec(select(func.count()).select_from(CommunityMember).where(
        CommunityMember.community_id == community_id, CommunityMember.status == MemberStatus.member)).one()


def summary(session: Session, community: Community, user: User) -> CommunityOut:
    m = membership(session, user.id)
    mine = m if m and m.community_id == community.id else None
    return CommunityOut(id=community.id, name=community.name, city=community.city,
                        photo_url=media_url(community.photo_path),
                        member_count=member_count(session, community.id),
                        my_status=mine.status if mine else None, is_admin=bool(mine and mine.is_admin))


def require_admin(session: Session, community: Community, user: User) -> None:
    m = membership(session, user.id)
    if m is None or m.community_id != community.id or not m.is_admin:
        raise HTTPException(status_code=403, detail="Only the community's admin can do that.")


def ensure_free(session: Session, user: User) -> None:
    m = membership(session, user.id)
    if m is not None:
        current = session.get(Community, m.community_id)
        raise HTTPException(status_code=409, detail=f"You're already in {current.name}. Leave it first to join another.")


@router.get("", response_model=list[CommunityOut])
def search(q: Optional[str] = None, user: User = Depends(current_user), session: Session = Depends(get_session)):
    query = select(Community).order_by(Community.name)
    if q and q.strip():
        query = query.where(func.lower(Community.name).contains(q.strip().lower()))
    return [summary(session, c, user) for c in session.exec(query.limit(50)).all()]


@router.post("", response_model=CommunityDetailOut, status_code=201)
def create(data: CommunityIn, user: User = Depends(current_user), session: Session = Depends(get_session)):
    ensure_free(session, user)
    duplicate = session.exec(select(Community).where(
        func.lower(Community.name) == data.name.lower(), func.lower(Community.city) == data.city.lower())).first()
    if duplicate is not None:
        raise HTTPException(status_code=409, detail=f"{duplicate.name} in {duplicate.city} already exists. Ask to join it instead.")
    community = Community(name=data.name, city=data.city, created_by=user.id)
    session.add(community)
    session.flush()
    session.add(CommunityMember(community_id=community.id, user_id=user.id, status=MemberStatus.member, is_admin=True))
    session.commit()
    return details(community.id, user, session)


@router.get("/{community_id}", response_model=CommunityDetailOut)
def details(community_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    base = summary(session, community, user)
    rows = session.exec(select(CommunityMember, User).join(User, User.id == CommunityMember.user_id)
                        .where(CommunityMember.community_id == community.id)
                        .order_by(CommunityMember.created_at)).all()
    is_member = base.my_status == MemberStatus.member
    photos = session.exec(select(CommunityPhoto, User).join(User, User.id == CommunityPhoto.uploader_id)
                          .where(CommunityPhoto.community_id == community.id)
                          .order_by(CommunityPhoto.created_at.desc())).all()
    return CommunityDetailOut(
        **base.model_dump(),
        members=[member_out(session, m, u) for m, u in rows if m.status == MemberStatus.member] if is_member else [],
        join_requests=[member_out(session, m, u) for m, u in rows if m.status == MemberStatus.pending] if base.is_admin else [],
        recap=[recap_out(p, u) for p, u in photos if in_recap(p)],
        pending_photos=[recap_out(p, u) for p, u in photos if p.status == PhotoStatus.pending] if base.is_admin else [],
    )


def member_out(session: Session, m: CommunityMember, u: User) -> MemberOut:
    household = household_of(session, u.id)
    has_buddy = has_active_buddy(session, u.id)
    return MemberOut(user_id=u.id, name=u.name, is_admin=m.is_admin, since=utc(m.created_at),
                     photo_url=media_url(u.photo_path), away_from_home=u.away_from_home,
                     has_buddy=has_buddy, is_volunteer=volunteer_of(session, u) is not None,
                     wants_buddy=bool(household and household.wants_buddy and not has_buddy))


# ---------------------------------------------------------------------------
# Weekly Recap
# ---------------------------------------------------------------------------

def expires_at(photo: CommunityPhoto) -> Optional[datetime]:
    if photo.pinned or photo.approved_at is None:
        return None
    return utc(photo.approved_at) + timedelta(days=RECAP_DAYS)


def in_recap(photo: CommunityPhoto) -> bool:
    """Approved, and either pinned or less than a week old."""
    if photo.status != PhotoStatus.approved:
        return False
    ends = expires_at(photo)
    return ends is None or ends > datetime.now(timezone.utc)


def recap_out(photo: CommunityPhoto, uploader: User) -> RecapPhotoOut:
    return RecapPhotoOut(id=photo.id, url=media_url(photo.path), caption=photo.caption,
                         uploader_name=uploader.name, status=photo.status, pinned=photo.pinned,
                         created_at=utc(photo.created_at), expires_at=expires_at(photo))


def require_member(session: Session, community: Community, user: User) -> CommunityMember:
    m = membership(session, user.id)
    if m is None or m.community_id != community.id or m.status != MemberStatus.member:
        raise HTTPException(status_code=403, detail="Only members of this community can do that.")
    return m


def photo_or_404(session: Session, community: Community, photo_id: int) -> CommunityPhoto:
    photo = session.get(CommunityPhoto, photo_id)
    if photo is None or photo.community_id != community.id:
        raise HTTPException(status_code=404, detail="Photo not found")
    return photo


@router.post("/{community_id}/recap", response_model=CommunityDetailOut, status_code=201)
async def add_recap_photo(community_id: int, file: UploadFile = File(...),
                          caption: str = Form("", max_length=120),
                          user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    m = require_member(session, community, user)
    path = await save_picture(file, PROFILES_DIR / "recap")
    now = datetime.now(timezone.utc)
    # The admin's own photos don't need approving.
    session.add(CommunityPhoto(community_id=community.id, uploader_id=user.id, path=media_name(path),
                               caption=caption.strip(),
                               status=PhotoStatus.approved if m.is_admin else PhotoStatus.pending,
                               approved_at=now if m.is_admin else None))
    session.commit()
    return details(community_id, user, session)


def admin_photo_action(community_id: int, photo_id: int, user: User, session: Session, change) -> CommunityDetailOut:
    community = get_or_404(session, community_id)
    require_admin(session, community, user)
    photo = photo_or_404(session, community, photo_id)
    change(photo)
    session.add(photo)
    session.commit()
    return details(community_id, user, session)


@router.post("/{community_id}/recap/{photo_id}/approve", response_model=CommunityDetailOut)
def approve_photo(community_id: int, photo_id: int, user: User = Depends(current_user),
                  session: Session = Depends(get_session)):
    def change(photo):
        photo.status, photo.approved_at = PhotoStatus.approved, datetime.now(timezone.utc)
    return admin_photo_action(community_id, photo_id, user, session, change)


@router.post("/{community_id}/recap/{photo_id}/reject", response_model=CommunityDetailOut)
def reject_photo(community_id: int, photo_id: int, user: User = Depends(current_user),
                 session: Session = Depends(get_session)):
    def change(photo):
        photo.status, photo.pinned = PhotoStatus.rejected, False
    return admin_photo_action(community_id, photo_id, user, session, change)


@router.post("/{community_id}/recap/{photo_id}/pin", response_model=CommunityDetailOut)
def pin_photo(community_id: int, photo_id: int, user: User = Depends(current_user),
              session: Session = Depends(get_session)):
    def change(photo):
        if photo.status != PhotoStatus.approved:
            raise HTTPException(status_code=400, detail="Approve the photo before pinning it.")
        photo.pinned = True
    return admin_photo_action(community_id, photo_id, user, session, change)


@router.post("/{community_id}/recap/{photo_id}/unpin", response_model=CommunityDetailOut)
def unpin_photo(community_id: int, photo_id: int, user: User = Depends(current_user),
                session: Session = Depends(get_session)):
    def change(photo):
        photo.pinned = False
    return admin_photo_action(community_id, photo_id, user, session, change)


@router.delete("/{community_id}/recap/{photo_id}", status_code=204)
def delete_recap_photo(community_id: int, photo_id: int, user: User = Depends(current_user),
                       session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    photo = photo_or_404(session, community, photo_id)
    m = membership(session, user.id)
    is_admin = m is not None and m.community_id == community.id and m.is_admin
    if photo.uploader_id != user.id and not is_admin:
        raise HTTPException(status_code=403, detail="Only the admin or whoever added it can remove a photo.")
    delete_media(photo.path)
    session.delete(photo)
    session.commit()
    return Response(status_code=204)


@router.post("/{community_id}/join", response_model=CommunityOut)
def join(community_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    ensure_free(session, user)
    session.add(CommunityMember(community_id=community.id, user_id=user.id))
    session.commit()
    return summary(session, community, user)


@router.post("/{community_id}/leave", status_code=204)
def leave(community_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    m = membership(session, user.id)
    if m is None or m.community_id != community.id:
        raise HTTPException(status_code=404, detail="You're not in this community.")
    session.delete(m)
    session.flush()
    remaining = session.exec(select(CommunityMember).where(
        CommunityMember.community_id == community.id, CommunityMember.status == MemberStatus.member
    ).order_by(CommunityMember.created_at)).all()
    if not remaining:
        # Nobody left: remove the community (and any pending requests to join it).
        session.exec(delete(CommunityMember).where(CommunityMember.community_id == community.id))
        session.delete(community)
    elif m.is_admin and not any(r.is_admin for r in remaining):
        remaining[0].is_admin = True   # the longest-standing member takes over
        session.add(remaining[0])
    session.commit()
    return Response(status_code=204)


def pending_request(session: Session, community: Community, user_id: int) -> CommunityMember:
    m = membership(session, user_id)
    if m is None or m.community_id != community.id or m.status != MemberStatus.pending:
        raise HTTPException(status_code=404, detail="No request to join from this person.")
    return m


@router.post("/{community_id}/requests/{user_id}/approve", response_model=CommunityDetailOut)
def approve(community_id: int, user_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    require_admin(session, community, user)
    m = pending_request(session, community, user_id)
    m.status = MemberStatus.member
    session.add(m)
    session.commit()
    return details(community_id, user, session)


@router.post("/{community_id}/requests/{user_id}/decline", response_model=CommunityDetailOut)
def decline(community_id: int, user_id: int, user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    require_admin(session, community, user)
    session.delete(pending_request(session, community, user_id))
    session.commit()
    return details(community_id, user, session)


@router.patch("/{community_id}", response_model=CommunityDetailOut)
def update(community_id: int, data: CommunityPatch, user: User = Depends(current_user),
           session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    require_admin(session, community, user)
    if data.name is not None:
        community.name = data.name.strip()
    session.add(community)
    session.commit()
    return details(community_id, user, session)


@router.put("/{community_id}/photo", response_model=CommunityDetailOut)
async def set_community_photo(community_id: int, file: UploadFile = File(...),
                              user: User = Depends(current_user), session: Session = Depends(get_session)):
    community = get_or_404(session, community_id)
    require_admin(session, community, user)
    new_name = media_name(await save_picture(file, PROFILES_DIR, max_side=800))
    delete_media(community.photo_path)
    community.photo_path = new_name
    session.add(community)
    session.commit()
    return details(community_id, user, session)
