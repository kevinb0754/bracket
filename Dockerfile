# Build static frontend files
FROM node:25-alpine AS builder
WORKDIR /app
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}
ENV NODE_ENV=production

# Copy frontend source and build it
COPY frontend ./frontend
RUN apk add pnpm && \
    cd frontend && \
    CI=true pnpm install && \
    pnpm build

# Build backend image
FROM python:3.14-alpine3.22
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN apk add --no-cache wget && rm -rf /var/cache/apk/*

# WORKDIR is /app
WORKDIR /app

# 1. Copy the CONTENTS of the backend folder into /app
# This ensures pyproject.toml is at /app/pyproject.toml
COPY backend/ .

# 2. This will now find the pyproject.toml in the current directory
RUN uv sync --no-dev --locked

# 3. Setup user and permissions
RUN addgroup --system bracket && \
    adduser --system bracket --ingroup bracket && \
    chown -R bracket:bracket /app

# 4. Copy built frontend from the builder stage
COPY --from=builder --chown=bracket:bracket /app/frontend/dist /app/frontend-dist

USER bracket
EXPOSE 8400

HEALTHCHECK --interval=3s --timeout=5s --retries=10 \
    CMD ["wget", "-O", "/dev/null", "http://0.0.0.0:8400/ping"]

# Explicitly tell gunicorn where the app is since we flattened the folder
CMD [ \
    "uv", \
    "run", \
    "--no-dev", \
    "--locked", \
    "--", \
    "gunicorn", \
    "-k", \
    "uvicorn.workers.UvicornWorker", \
    "bracket.app:app", \
    "--bind", \
    "0.0.0.0:8400", \
    "--workers", \
    "1" \
]
