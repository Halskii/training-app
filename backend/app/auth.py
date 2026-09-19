import logging

from fastapi import Header, HTTPException

from app.db import get_supabase

logger = logging.getLogger(__name__)


def current_user_id(authorization: str = Header(default="")) -> str:
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")

    # Outside the try: a misconfigured Supabase client should be a 500, not a 401.
    sb = get_supabase()
    try:
        res = sb.auth.get_user(token)
    except Exception as e:
        logger.warning("Token validation failed: %s: %s", type(e).__name__, e)
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    if res is None or res.user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return res.user.id
