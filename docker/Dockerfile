# Base images mirrored to ACR (opencsg_public) so CI can pull without Docker Hub.
# Host: opencsg-registry.cn-beijing.cr.aliyuncs.com — push local pulls with:
#   docker tag golang:1.25-alpine .../opencsg_public/golang:1.25-alpine
#   docker tag alpine:3.23 .../opencsg_public/alpine:3.23
#
# Runtime base must be multi-arch (arm64 + amd64). ACR opencsg_public/alpine:3.23 is amd64-only;
# default to official alpine:3.23. Override RUNTIME_BASE when arm64 is mirrored to ACR.
ARG RUNTIME_BASE=alpine:3.23

# ============================================================
# Stage 1: Build the picoclaw binary
# ============================================================
FROM opencsg-registry.cn-beijing.cr.aliyuncs.com/opencsg_public/golang:1.25-alpine AS builder

# Alpine apk: use Aliyun mirror instead of dl-cdn (often slow or flaky in mainland CN).
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache git make

# Go modules: default proxy/sumdb can be slow or unreachable in CN.
ENV GOPROXY=https://goproxy.cn,direct
ENV GOSUMDB=sum.golang.google.cn
ENV GIT_TERMINAL_PROMPT=0

WORKDIR /src

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN make build

# ============================================================
# Stage 1.5: Download platform-specific csgclaw-cli release tarball
# ============================================================
FROM ${RUNTIME_BASE} AS csgclaw-cli
ARG TARGETARCH
# Override to pin a release, e.g. https://csgclaw.opencsg.com/releases/v1.0.0
ARG CSGCLAW_CLI_BASE_URL=https://csgclaw.opencsg.com/releases/latest
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
  && apk add --no-cache ca-certificates curl \
  && curl -fSL "${CSGCLAW_CLI_BASE_URL}/linux/${TARGETARCH}?package=csgclaw-cli" -o /tmp/csgclaw-cli.tar.gz \
  && mkdir -p /tmp/extract \
  && tar -xzf /tmp/csgclaw-cli.tar.gz -C /tmp/extract \
  && set -eu; \
     bin="$(find /tmp/extract -type f \( -name csgclaw-cli -o -name "csgclaw-cli_linux_${TARGETARCH}" \) | head -n1)"; \
     if [ -z "$bin" ]; then bin="$(find /tmp/extract -type f -perm -111 | head -n1)"; fi; \
     if [ -z "$bin" ]; then echo "csgclaw-cli binary not found in archive"; ls -laR /tmp/extract; exit 1; fi; \
     install -m0755 "$bin" /csgclaw-cli

# ============================================================
# Stage 2: Minimal runtime image
# ============================================================
FROM ${RUNTIME_BASE}
ARG TARGETARCH
# Override to pin a release API, e.g. .../releases/v1.92.0
ARG GLAB_RELEASE_API_URL=https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache ca-certificates curl python3 tini tzdata

# glab (GitLab CLI): resolve latest release at build time and install the matching APK.
RUN set -eu; \
  case "${TARGETARCH}" in \
    arm64|amd64) ;; \
    *) echo "glab: unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  version="$(python3 -c "import json,urllib.request; r=json.load(urllib.request.urlopen('${GLAB_RELEASE_API_URL}')); print(r['tag_name'].lstrip('v'))")"; \
  enc_ver="$(echo "$version" | sed 's/\./%2E/g')"; \
  glab_apk_url="https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${enc_ver}/glab_${version}_linux_${TARGETARCH}.apk"; \
  curl -fsSL "$glab_apk_url" -o /tmp/glab.apk; \
  apk add --no-cache --allow-untrusted /tmp/glab.apk; \
  rm -f /tmp/glab.apk; \
  glab --version

ENV GLAB_TELEMETRY_DISABLED=1

# Health check (use 127.0.0.1: gateway listens on IPv4 only; "localhost" may resolve to ::1 and fail)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:18790/health || exit 1

# Copy binary
COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw
COPY --from=csgclaw-cli /csgclaw-cli /usr/local/bin/csgclaw-cli

# Create non-root user and group
RUN addgroup -g 1000 picoclaw && \
    adduser -D -u 1000 -G picoclaw picoclaw

# Switch to non-root user
USER picoclaw

# Run onboard to create initial directories and config
RUN /usr/local/bin/picoclaw onboard && \
    find /home/picoclaw/.picoclaw/workspace/skills -mindepth 1 -maxdepth 1 \
      ! -name 'manager-worker-dispatch' ! -name 'basics' -exec rm -rf {} +

# Bundle the default config into the image
COPY --chown=picoclaw:picoclaw docker/config/config.json /home/picoclaw/.picoclaw/config.json

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sleep", "infinity"]

# CMD ["picoclaw", "gateway", "-d"]
