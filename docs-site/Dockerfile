# The tutorial, served from the cluster next to the app it documents.
# Build context is docs-site/ (it has its own lockfile — it is not part of the
# npm workspace):
#
#   docker build -t pulse-docs docs-site
FROM node:20-alpine AS builder

WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

# Served under /docs behind the ingress, so Docusaurus must generate its links
# with that prefix. Trailing slash matters — Docusaurus requires it.
ENV DOCS_BASE_URL=/docs/
RUN npm run build

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
# baseUrl is /docs/, so the built site lives at that path on disk too.
COPY --from=builder /build/build /usr/share/nginx/html/docs

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
