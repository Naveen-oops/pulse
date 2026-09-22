# Build the static bundle, then serve it from nginx.
# API routing is the ingress's job — nginx here only serves files.
#
# IMPORTANT: build from the REPO ROOT, not from this directory. The npm
# workspace keeps a single lockfile at the root, and `npm ci` needs it:
#
#   docker build -f packages/web/Dockerfile -t pulse-web .

FROM node:20-alpine AS builder

WORKDIR /build

# Manifests first, so `npm ci` stays cached until dependencies actually change.
COPY package.json package-lock.json ./
COPY packages/web/package.json packages/web/
RUN npm ci --no-audit --no-fund

# Then the source, which changes on every commit.
COPY packages/web packages/web
RUN npm run build --workspace pulse-web

FROM nginx:1.27-alpine

COPY packages/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /build/packages/web/dist /usr/share/nginx/html

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
