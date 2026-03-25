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

# Set the workdir to /app/backend so uv finds the pyproject.toml
WORKDIR /app/backend

# Copy the backend folder from your repo into the current workdir
COPY backend/ .

# Now uv sync will work because it's sitting next to pyproject.toml
RUN uv sync --no-dev --locked

# Setup user and permissions for the whole /app folder
RUN addgroup --system bracket && \
    adduser --system bracket --ingroup bracket && \
    chown -R bracket:bracket /app

# Copy built frontend from the builder stage
COPY --from=builder --chown=bracket:bracket /app/frontend/dist /app/frontend-dist

USER bracket
EXPOSE 8400

HEALTHCHECK --interval=3s --timeout=5s --retries=10 \
    CMD ["wget", "-O", "/dev/null", "http://0.0.0.0:8400/ping"]

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
