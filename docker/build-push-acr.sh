#!/usr/bin/env bash
# Multi-arch build + push for opencsghq/picoclaw (matches .gitlab/ci.yml).
set -euo pipefail

export TZ=Asia/Shanghai
export DOCKER_BUILDKIT=1
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

ACR_REGISTRY="${ACR_REGISTRY:-opencsg-registry.cn-beijing.cr.aliyuncs.com}"
DOCKER_IMAGE="${DOCKER_IMAGE:-${ACR_REGISTRY}/opencsghq/picoclaw-glab}"
DOCKER_PLATFORMS="${DOCKER_PLATFORMS:-linux/amd64,linux/arm64}"

# Tag: YYYY.M.D.0 (same as deployed tags like 2026.4.29.0)
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y).$(date +%-m).$(date +%-d).0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILDER_NAME="${BUILDX_BUILDER:-picoclaw-mx-local}"

cd "${ROOT_DIR}"

echo "IMAGE_TAG=${IMAGE_TAG}"
echo "DOCKER_IMAGE=${DOCKER_IMAGE}"
echo "DOCKER_PLATFORMS=${DOCKER_PLATFORMS}"

if ! docker info >/dev/null 2>&1; then
  echo "error: docker is not running" >&2
  exit 1
fi

if [ "${SKIP_DOCKER_LOGIN:-}" != "1" ] && [ "${SKIP_DOCKER_LOGIN:-}" != "true" ]; then
  if [ -n "${ACR_PASSWORD:-}" ] && [ -n "${ACR_USERNAME:-}" ]; then
    echo "${ACR_PASSWORD}" | docker login -u "${ACR_USERNAME}" --password-stdin "${ACR_REGISTRY}"
  else
    echo "using existing docker credentials for ${ACR_REGISTRY} (set ACR_USERNAME+ACR_PASSWORD to login)"
  fi
fi

if [ "${SKIP_BINFMT_INSTALL:-}" != "true" ] && [ "${SKIP_BINFMT_INSTALL:-}" != "1" ]; then
  BINFMT_IMAGE="${BINFMT_IMAGE:-${ACR_REGISTRY}/opencsg_public/binfmt:latest}"
  echo "Installing binfmt from ${BINFMT_IMAGE}"
  docker run --rm --privileged "${BINFMT_IMAGE}" --install all
fi

docker buildx rm "${BUILDER_NAME}" 2>/dev/null || true
BUILDKIT_CI_IMAGE="${BUILDKIT_CI_IMAGE:-${ACR_REGISTRY}/opencsg_public/moby-buildkit:buildx-stable-1}"
echo "BuildKit image: ${BUILDKIT_CI_IMAGE}"
docker buildx create --name "${BUILDER_NAME}" --driver docker-container \
  --driver-opt "image=${BUILDKIT_CI_IMAGE}" --bootstrap --use

cleanup() {
  docker buildx rm "${BUILDER_NAME}" 2>/dev/null || true
}
trap cleanup EXIT

docker buildx build \
  --platform "${DOCKER_PLATFORMS}" \
  -f docker/Dockerfile \
  --build-arg "RUNTIME_ALPINE_BASE_IMAGE=${RUNTIME_ALPINE_BASE_IMAGE:-opencsg-registry.cn-beijing.cr.aliyuncs.com/opencsghq/alpine:3.23}" \
  -t "${DOCKER_IMAGE}:${IMAGE_TAG}" \
  --provenance=false \
  --sbom=false \
  --push \
  .

echo "pushed: ${DOCKER_IMAGE}:${IMAGE_TAG}"
