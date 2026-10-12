"""
Who is asking? (Demo identity)

RollCall has no real login yet (that's out of scope for the challenge). The
app tells the server who it is acting as with two headers:

    X-Demo-Role: resident | buddy | responder
    X-Demo-Id:   the household id (resident) or volunteer id (buddy)

Every endpoint gets a Viewer and checks it against the privacy rules in
privacy.py. In a real deployment these headers would be replaced by a proper
sign-in, and the privacy rules would stay exactly the same.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Optional

from fastapi import Header, HTTPException


class Role(str, Enum):
    resident = "resident"
    buddy = "buddy"
    responder = "responder"


@dataclass
class Viewer:
    role: Role
    id: Optional[int] = None   # household id for a resident, volunteer id for a buddy


def get_viewer(
    x_demo_role: Optional[str] = Header(None),
    x_demo_id: Optional[int] = Header(None),
) -> Viewer:
    """FastAPI dependency: read the demo identity headers."""
    if x_demo_role is None:
        raise HTTPException(status_code=401, detail="Choose a role first (missing X-Demo-Role).")
    try:
        role = Role(x_demo_role)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Unknown role: {x_demo_role}")
    if role != Role.responder and x_demo_id is None:
        raise HTTPException(status_code=401, detail="Missing X-Demo-Id for this role.")
    return Viewer(role=role, id=x_demo_id)
