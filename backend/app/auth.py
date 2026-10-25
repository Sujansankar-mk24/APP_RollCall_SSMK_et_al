"""
Accounts: passwords, sign-in tokens, and "who is asking?".

Passwords
    A password is never stored. Instead we store a random "salt" plus the
    result of scrypt(password + salt), a hash that is deliberately slow to
    compute, so even someone who stole the database couldn't quickly guess
    passwords. To check a sign-in, we hash what was typed the same way and
    compare.

Tokens ("remember me")
    After signing up or in, the app gets a long random token and keeps it in
    the iPhone's Keychain. Every request sends it in a header:
        Authorization: Bearer <token>
    The server stores only a hash of the token, so the database alone can't
    be used to sign in as anyone. Signing out deletes the token.
"""

import hashlib
import hmac
import secrets
from typing import Optional

from fastapi import Depends, Header, HTTPException
from sqlmodel import Session, select

from app.database import get_session
from app.models import AuthToken, User

MIN_PASSWORD_LENGTH = 8


# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------

def _scrypt(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)


def hash_password(password: str) -> str:
    """Returns "salt$hash" (both as hex), safe to store."""
    salt = secrets.token_bytes(16)
    return f"{salt.hex()}${_scrypt(password, salt).hex()}"


def check_password(password: str, stored: str) -> bool:
    try:
        salt_hex, hash_hex = stored.split("$")
    except ValueError:
        return False   # e.g. demo accounts, which have no usable password
    # compare_digest takes the same time whether the first or last byte differs,
    # so timing can't reveal how close a guess was.
    return hmac.compare_digest(_scrypt(password, bytes.fromhex(salt_hex)).hex(), hash_hex)


# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------

def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue_token(session: Session, user: User) -> str:
    """Create a new sign-in token for this user. The caller commits."""
    token = secrets.token_urlsafe(32)
    session.add(AuthToken(user_id=user.id, token_hash=_token_hash(token)))
    return token


def revoke_token(session: Session, token: str) -> None:
    for row in session.exec(select(AuthToken).where(AuthToken.token_hash == _token_hash(token))).all():
        session.delete(row)


def _bearer(authorization: Optional[str]) -> Optional[str]:
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    return None


def current_user(
    authorization: Optional[str] = Header(None),
    session: Session = Depends(get_session),
) -> User:
    """FastAPI dependency: the signed-in user, or 401 if there isn't one."""
    token = _bearer(authorization)
    row = session.exec(select(AuthToken).where(AuthToken.token_hash == _token_hash(token))).first() if token else None
    user = session.get(User, row.user_id) if row else None
    if user is None:
        raise HTTPException(status_code=401, detail="Please sign in again.")
    return user


def optional_user(
    authorization: Optional[str] = Header(None),
    session: Session = Depends(get_session),
) -> Optional[User]:
    """The signed-in user if there is one, or None (for pages anyone can see)."""
    token = _bearer(authorization)
    row = session.exec(select(AuthToken).where(AuthToken.token_hash == _token_hash(token))).first() if token else None
    return session.get(User, row.user_id) if row else None


def current_token(authorization: Optional[str] = Header(None)) -> str:
    token = _bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Please sign in again.")
    return token
