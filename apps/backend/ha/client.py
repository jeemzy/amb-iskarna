"""Home Assistant WebSocket client — auth test and light test."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

import websockets

from apps.backend.settings import settings

logger = logging.getLogger(__name__)

_MSG_ID = 0


def _next_id() -> int:
    global _MSG_ID
    _MSG_ID += 1
    return _MSG_ID


async def _connect_and_auth(timeout: float = 10.0):
    """Open a WebSocket to HA, authenticate, and return the connection."""
    url = settings.env.ha_url
    token = settings.env.ha_token
    if not token:
        raise ValueError("HA_TOKEN is not set")

    ws = await asyncio.wait_for(
        websockets.connect(url, max_size=2**22),
        timeout=timeout,
    )
    try:
        # HA sends auth_required on connect
        greeting = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if greeting.get("type") != "auth_required":
            raise RuntimeError(f"Unexpected greeting: {greeting}")

        await ws.send(json.dumps({"type": "auth", "access_token": token}))
        auth_result = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))

        if auth_result.get("type") == "auth_ok":
            logger.info("HA auth succeeded — version %s", auth_result.get("ha_version"))
            return ws
        elif auth_result.get("type") == "auth_invalid":
            raise PermissionError(
                f"HA auth failed: {auth_result.get('message', 'invalid token')}"
            )
        else:
            raise RuntimeError(f"Unexpected auth response: {auth_result}")
    except Exception:
        await ws.close()
        raise


async def test_connection() -> dict[str, Any]:
    """Test HA connectivity and auth. Returns a status dict."""
    try:
        ws = await _connect_and_auth()
        await ws.close()
        return {"ok": True, "message": "Connected and authenticated"}
    except Exception as exc:
        logger.warning("HA connection test failed: %s", exc)
        return {"ok": False, "message": str(exc)}


async def test_light(color: tuple[int, int, int] = (255, 180, 50)) -> dict[str, Any]:
    """Send a test color to the configured lamp entity."""
    entity_id = settings.env.lamp_entity_id
    if not entity_id:
        return {"ok": False, "message": "LAMP_ENTITY_ID is not set"}

    try:
        ws = await _connect_and_auth()
        msg_id = _next_id()
        payload = {
            "id": msg_id,
            "type": "call_service",
            "domain": "light",
            "service": "turn_on",
            "service_data": {"rgb_color": list(color)},
            "target": {"entity_id": entity_id},
        }
        await ws.send(json.dumps(payload))
        result = json.loads(await asyncio.wait_for(ws.recv(), timeout=10.0))
        await ws.close()

        if result.get("success"):
            return {"ok": True, "message": f"Sent color {list(color)} to {entity_id}"}
        else:
            err = result.get("error", {})
            return {
                "ok": False,
                "message": f"Service call failed: {err.get('message', result)}",
            }
    except Exception as exc:
        logger.warning("HA light test failed: %s", exc)
        return {"ok": False, "message": str(exc)}
