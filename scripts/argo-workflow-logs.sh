#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# Archived step logs for a finished Argo workflow.
#
# `argo logs` streams live pods only, so it returns nothing once podGC deletes
# them. These come from the artifact repository instead (see
# apps/scaleodm/helm/values.yaml -> argo.artifactRepository).
#
# Needs only kubectl and curl: the S3 credentials are the ones the workflow
# archived with, read from the cluster, so there is no aws CLI or local profile.
#
# Usage:
#   bash argo-workflow-logs.sh <workflow-name> [namespace]
#
# Namespace defaults to the current kubectl context. Overrides:
# ARGO_LOGS_BUCKET, ARGO_LOGS_REGION.
#
# Fish users: ./wflogs.fish is the same thing as an autoloaded function.
#   ln -s "$PWD/scripts/wflogs.fish" ~/.config/fish/functions/wflogs.fish
#   wflogs <workflow-name> [namespace]
# -------------------------------------------------------------

BUCKET="${ARGO_LOGS_BUCKET:-hotosm-argo-logs}"
REGION="${ARGO_LOGS_REGION:-us-east-1}"

if [[ $# -lt 1 ]]; then
  echo "usage: bash argo-workflow-logs.sh <workflow-name> [namespace]" >&2
  exit 1
fi

WORKFLOW="$1"
NAMESPACE="${2:-}"
if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
fi
NAMESPACE="${NAMESPACE:-oam-staging}"

mapfile -t CREDS < <(
  kubectl -n "$NAMESPACE" get secret argo-logs-s3-creds \
    -o jsonpath='{.data.AWS_ACCESS_KEY_ID}{"\n"}{.data.AWS_SECRET_ACCESS_KEY}' \
    2>/dev/null || true
)
if [[ ${#CREDS[@]} -lt 2 ]]; then
  echo "No argo-logs-s3-creds in namespace $NAMESPACE" >&2
  exit 1
fi
# Passed to curl on stdin, not argv, so it stays out of ps.
CONFIG="user = \"$(base64 -d <<<"${CREDS[0]}"):$(base64 -d <<<"${CREDS[1]}")\""

SIGV4="aws:amz:${REGION}:s3"
HOST="${BUCKET}.s3.${REGION}.amazonaws.com"
PREFIX="${NAMESPACE}/${WORKFLOW}/"

LISTING="$(
  curl -sS --aws-sigv4 "$SIGV4" -K - \
    "https://${HOST}/?list-type=2&prefix=${PREFIX}" <<<"$CONFIG"
)"
if [[ "$LISTING" =~ \<Code\>([^\<]+)\</Code\> ]]; then
  echo "S3 refused the listing: ${BASH_REMATCH[1]}" >&2
  exit 1
fi

# Lexicographic from S3, which groups the steps by name.
mapfile -t KEYS < <(grep -o '<Key>[^<]*</Key>' <<<"$LISTING" | sed 's/<[^>]*>//g')
if [[ ${#KEYS[@]} -eq 0 ]]; then
  echo "No archived logs under s3://${BUCKET}/${PREFIX}" >&2
  echo "Check the namespace, or that log archiving was on for that run." >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# One curl for every object, so the connection is reused; each URL is signed.
FETCH=()
for i in "${!KEYS[@]}"; do
  FETCH+=("https://${HOST}/${KEYS[$i]}" -o "${WORKDIR}/${i}")
done
curl -sS --aws-sigv4 "$SIGV4" -K - "${FETCH[@]}" <<<"$CONFIG"

for i in "${!KEYS[@]}"; do
  pod="${KEYS[$i]%/*}"
  echo "===== ${pod##*/} ====="
  body="$(cat "${WORKDIR}/${i}" 2>/dev/null || true)"
  if [[ "$body" =~ \<Code\>([^\<]+)\</Code\> ]]; then
    echo "(S3 refused this object: ${BASH_REMATCH[1]})" >&2
  else
    printf '%s\n' "$body"
  fi
  echo
done
