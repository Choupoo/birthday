# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS build
WORKDIR /app

# Older Parcel dependencies need native compilation on Linux ARM64.
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 make g++ ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --include=dev --no-audit --no-fund

COPY builder ./builder
COPY src ./src
COPY local ./local

# Keep the original .env out of image layers and the final web root.
# Each project is served at the root of its own subdomain.
ARG PUBLIC_URL=/
RUN --mount=type=secret,id=birthday_env,target=/app/.env,required=true \
    npm run init-index-local && \
    npm run build:parcel -- --public-url "$PUBLIC_URL" --no-source-maps

FROM nginx:stable-alpine
# Compose mounts the centralized nginx/projects/birthday.conf at runtime.
COPY --from=build /app/dist/ /usr/share/nginx/html/
EXPOSE 80
