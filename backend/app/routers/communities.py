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
  PATCH  /communities/{id}                    admin: allow buddies from outside?

Each person belongs to (or is asking to join) one community at a time.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session, delete, func, select

from app.auth import current_user
from app.database import get_session
from app.models import Community, CommunityMember, MemberStatus, User
from app.privacy import membership
from app.schemas import CommunityDetailOut, CommunityIn, CommunityOut, CommunityPatch, MemberOut
from app.services.households import utc

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
    as_out = lambda m, u: MemberOut(user_id=u.id, name=u.name, is_admin=m.is_admin, since=utc(m.created_at))
    is_member = base.my_status == MemberStatus.member
    return CommunityDetailOut(
        **base.model_dump(),
        allow_outside_buddies=community.allow_outside_buddies,
        members=[as_out(m, u) for m, u in rows if m.status == MemberStatus.member] if is_member else [],
        join_requests=[as_out(m, u) for m, u in rows if m.status == MemberStatus.pending] if base.is_admin else [],
    )


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
    community.allow_outside_buddies = data.allow_outside_buddies
    session.add(community)
    session.commit()
    return details(community_id, user, session)
