# syntax=docker/dockerfile:1.7
# Multi-stage build: dependencies are installed in a builder stage, and only the
# virtualenv and source code are copied into the final image, which runs as a
# non-root user.

ARG PYTHON_IMAGE=python:3.13-slim

FROM ${PYTHON_IMAGE} AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

FROM ${PYTHON_IMAGE} AS runtime
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.source="https://github.com/sk-haaga/azure-golden-path-template" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.title="sample-api"

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    GIT_SHA=${GIT_SHA} \
    PORT=8000

RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home app

COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY --chown=app:app src ./src

USER 10001
EXPOSE 8000
CMD ["sh", "-c", "exec uvicorn sample_api.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --no-server-header"]
