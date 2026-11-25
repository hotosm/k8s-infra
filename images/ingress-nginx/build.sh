#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source versions.env

REGISTRY="${REGISTRY:-ghcr.io/hotosm/k8s-infra/ingress-nginx}"
BASE="$REGISTRY/nginx:$NGINX_BASE_TAG"
CONTROLLER="$REGISTRY/controller:$CONTROLLER_TAG"
TRIVY="${TRIVY:-trivy}"
ALPINE=alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

SRC=work/ingress-nginx
OUT=work/out
mkdir -p "$OUT"

die() { echo "error: $*" >&2; exit 1; }
digest() { docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -r .digest; }

fetch() {
  [[ -d $SRC ]] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$FORK_REF" "$FORK_REPO" "$SRC"
  [[ $(git -C "$SRC" rev-parse HEAD) == "$FORK_COMMIT" ]] || die "$FORK_REF does not point to $FORK_COMMIT"
  [[ $(cat "$SRC/images/nginx/TAG") == "$NGINX_BASE_TAG" ]] || die "nginx base tag mismatch"
  [[ $(ls "$SRC/images/nginx/rootfs/patches" | wc -l) == "$NGINX_PATCHES" ]] || die "nginx patch count mismatch"
}

base() {
  docker buildx build --builder default --platform linux/amd64 --load --no-cache --progress plain \
    -t "$BASE" "$SRC/images/nginx/rootfs" 2>&1 | tee "$OUT/base.log"
  grep -oE ' Patch: [^ ]+' "$OUT/base.log" | awk '{print $2}' | sort > "$OUT/patches.txt" || true
  diff -q <(ls "$SRC/images/nginx/rootfs/patches" | sort) "$OUT/patches.txt" >/dev/null || die "not all patches applied"
  ! grep -qE 'FAILED|\.rej|Reversed' "$OUT/base.log" || die "a patch failed to apply"
}

binaries() {
  # run-in-docker.sh mounts $HOME/.kube into the container, so give it an empty HOME
  mkdir -p work/home
  docker run --rm -v "$PWD/$SRC/rootfs:/r" "$ALPINE" rm -rf /r/bin
  (cd "$SRC" && env HOME="$PWD/../home" ARCH=amd64 E2E_IMAGE="$GO_IMAGE" USE_SHELL=/bin/sh \
    build/run-in-docker.sh MAC_OS= PKG=k8s.io/ingress-nginx ARCH=amd64 TAG="$CONTROLLER_TAG" \
    COMMIT_SHA="git-${FORK_COMMIT:0:7}" REPO_INFO="$FORK_REPO" build/build.sh)
}

controller() {
  make -C "$SRC" image REGISTRY=local TAG="$CONTROLLER_TAG" ARCH=amd64 BASE_IMAGE="${1:-$BASE}" \
    BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
  docker tag "local/controller:$CONTROLLER_TAG" "$CONTROLLER"
  docker rmi -f "local/controller:$CONTROLLER_TAG" >/dev/null
}

verify() {
  docker image inspect "$BASE" "$CONTROLLER" | jq -e '(.[0].RootFS.Layers) as $b | .[1].RootFS.Layers[:($b | length)] == $b' >/dev/null \
    || die "controller is not built on $BASE"

  [[ $(docker run --rm --entrypoint nginx "$CONTROLLER" -v 2>&1) == *"nginx/$NGINX_VERSION"* ]] || die "wrong nginx version"
  [[ $(docker run --rm --entrypoint /nginx-ingress-controller "$CONTROLLER" --version) == *"$CONTROLLER_TAG"* ]] \
    || die "wrong controller version"
  "$TRIVY" image -q --format json --list-all-pkgs "$CONTROLLER" \
    | jq -e --arg v "v$GO_VERSION" '[.Results[].Packages[]? | select(.Name == "stdlib") | .Version] | unique == [$v]' >/dev/null \
    || die "binaries are not built with Go $GO_VERSION"

  for image in "$BASE" "$CONTROLLER"; do
    "$TRIVY" image -q --skip-db-update --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 "$image"
  done
  echo "ok: controller $CONTROLLER_TAG, nginx $NGINX_VERSION ($NGINX_PATCHES patches), go $GO_VERSION"
}

push() {
  docker push -q "$BASE" >/dev/null
  controller "$BASE@$(digest "$BASE")"
  verify
  docker push -q "$CONTROLLER" >/dev/null
  if [[ -n ${EXTRA_TAG:-} ]]; then
    for image in "$BASE" "$CONTROLLER"; do
      docker tag "$image" "${image%:*}:$EXTRA_TAG"
      docker push -q "${image%:*}:$EXTRA_TAG" >/dev/null
    done
  fi
  printf 'BASE_IMAGE=%s@%s\nCONTROLLER_IMAGE=%s@%s\n' "$BASE" "$(digest "$BASE")" "$CONTROLLER" "$(digest "$CONTROLLER")" \
    | tee "$OUT/images.env"
}

clean() {
  docker run --rm -v "$PWD:/r" "$ALPINE" rm -rf /r/work
}

case "${1:-build}" in
  build) fetch; base; binaries; controller ;;
  verify | push | clean) "$1" ;;
  *) die "usage: $0 [build|verify|push|clean]" ;;
esac
