"""All Milestone-1 API routes."""

from __future__ import annotations

from fastapi import APIRouter

from apps.backend.settings import settings
from apps.backend.capture.display import displays_as_dicts
from apps.backend.ha import client as ha_client

router = APIRouter(prefix="/api")


# ── Health ────────────────────────────────────────────────────────────────


@router.get("/health")
async def health():
    return {"status": "ok"}


# ── Displays ──────────────────────────────────────────────────────────────


@router.get("/displays")
async def list_displays():
    return displays_as_dicts()


# ── Settings ──────────────────────────────────────────────────────────────


@router.get("/settings")
async def get_settings():
    return settings.capture.model_dump()


@router.put("/settings")
async def update_settings(patch: dict):
    updated = settings.update_capture(patch)
    return updated.model_dump()


# ── Home Assistant ────────────────────────────────────────────────────────


@router.post("/ha/test-connection")
async def ha_test_connection():
    return await ha_client.test_connection()


@router.post("/ha/test-light")
async def ha_test_light():
    return await ha_client.test_light()
