"""A small HTTP API used to prove the golden path end to end.

It is deliberately boring: health and readiness probes for Azure Container
Apps, a version endpoint that reports exactly which build is running, and one
business-style endpoint so there is something real to test.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import UTC, datetime

from fastapi import FastAPI, Request
from pydantic import BaseModel, Field

from sample_api import __version__

SERVICE_NAME = os.getenv("SERVICE_NAME", "sample-api")
ENVIRONMENT = os.getenv("APP_ENVIRONMENT", "local")
GIT_SHA = os.getenv("GIT_SHA", "unknown")
STARTED_AT = datetime.now(UTC)


class JsonFormatter(logging.Formatter):
    """One JSON object per line, which Log Analytics parses without extra setup."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "service": SERVICE_NAME,
            "env": ENVIRONMENT,
        }
        extra = getattr(record, "fields", None)
        if isinstance(extra, dict):
            payload.update(extra)
        return json.dumps(payload)


def _configure_logging() -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("sample_api")
    logger.handlers = [handler]
    logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))
    logger.propagate = False
    return logger


log = _configure_logging()

app = FastAPI(
    title="Sample API",
    version=__version__,
    docs_url="/docs" if ENVIRONMENT != "production" else None,
    redoc_url=None,
)


@app.middleware("http")
async def access_log(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    if request.url.path not in {"/healthz", "/readyz"}:
        log.info(
            "request",
            extra={
                "fields": {
                    "method": request.method,
                    "path": request.url.path,
                    "status": response.status_code,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                }
            },
        )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "no-store"
    return response


class Health(BaseModel):
    status: str


class VersionInfo(BaseModel):
    service: str
    version: str
    git_sha: str
    environment: str
    started_at: datetime


class Quote(BaseModel):
    """Shipping quote request: a stand-in for real business logic."""

    weight_kg: float = Field(gt=0, le=1000)
    distance_km: float = Field(gt=0, le=20000)
    express: bool = False


class QuoteResult(BaseModel):
    price_eur: float
    currency: str = "EUR"


@app.get("/healthz", response_model=Health, tags=["ops"])
def healthz() -> Health:
    """Liveness probe: the process is up."""
    return Health(status="ok")


@app.get("/readyz", response_model=Health, tags=["ops"])
def readyz() -> Health:
    """Readiness probe: the service can take traffic."""
    return Health(status="ready")


@app.get("/version", response_model=VersionInfo, tags=["ops"])
def version() -> VersionInfo:
    """Which build is running. The pipeline's smoke test checks git_sha."""
    return VersionInfo(
        service=SERVICE_NAME,
        version=__version__,
        git_sha=GIT_SHA,
        environment=ENVIRONMENT,
        started_at=STARTED_AT,
    )


@app.post("/api/v1/quotes", response_model=QuoteResult, tags=["api"])
def create_quote(quote: Quote) -> QuoteResult:
    base = 4.90 + quote.weight_kg * 0.85 + quote.distance_km * 0.012
    if quote.express:
        base *= 1.5
    return QuoteResult(price_eur=round(base, 2))


@app.get("/", include_in_schema=False)
def root() -> dict[str, str]:
    return {"service": SERVICE_NAME, "docs": "/docs", "health": "/healthz"}
