"""Sample service with production basics: health/readiness probes,
Prometheus metrics and structured JSON logs.
Graceful shutdown: the pod's preStop hook sleeps so the ALB deregisters the
target first, then uvicorn handles SIGTERM and finishes in-flight requests."""
import json
import logging
import os
import socket
import time

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_VERSION = os.getenv("APP_VERSION", "dev")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        return json.dumps({
            "ts": self.formatTime(record),
            "level": record.levelname,
            "msg": record.getMessage(),
            "version": APP_VERSION,
        })


handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
log = logging.getLogger("app")
log.addHandler(handler)
log.setLevel(logging.INFO)

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "path", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Request latency", ["path"])

app = FastAPI(title="sample-app", version=APP_VERSION)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    path = request.url.path
    if path not in ("/metrics", "/healthz", "/readyz"):
        LATENCY.labels(path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, path, response.status_code).inc()
    return response


@app.get("/")
def root():
    return {
        "service": "sample-app",
        "version": APP_VERSION,
        "environment": ENVIRONMENT,
        "pod": socket.gethostname(),
    }


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    # Extend with real dependency checks (DB, cache) in a real service.
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
