# The checker only uses the Python standard library, so the image is a plain
# Alpine Python base with the source copied in: small, fast to build on each
# workflow run, and nothing extra for Trivy to flag.
FROM python:3.13-alpine

RUN apk upgrade --no-cache \
    && adduser -D -u 10001 checker

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/require-tags/src

COPY src /opt/require-tags/src

# GitHub runs Docker actions with the workspace mounted at /github/workspace
# and sets it as the working directory, so relative plan paths resolve there.
# The action runs as root by default because the mounted files are owned by
# the runner user; the checker only reads the plan and appends to the files
# GitHub provides for outputs and the job summary.
ENTRYPOINT ["python", "-m", "require_tags"]
