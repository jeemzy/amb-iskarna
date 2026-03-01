"""Amb-Iskarna backend — FastAPI entrypoint.

Run with:
    uvicorn apps.backend.main:app --host 0.0.0.0 --port 8765
"""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from apps.backend.settings import settings
from apps.backend.api.routes import router as api_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Amb-Iskarna",
    description="Ambient-light controller for Iskarna lamp via Home Assistant",
    version="0.1.0",
)

# -- CORS ------------------------------------------------------------------
origins = [o.strip() for o in settings.env.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -- Routers ---------------------------------------------------------------
app.include_router(api_router)
