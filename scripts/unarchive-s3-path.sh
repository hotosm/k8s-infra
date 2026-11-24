#!/usr/bin/env bash
set -euo pipefail
# -------------------------------------------------------------
# Restore S3 Intelligent-Tiering archived objects under one or more prefixes
# Usage:
#   AWS_PROFILE=admin bash unarchive-s3-path.sh <bucket-name> <prefix>...
#
# Optional: EXCLUDE=<grep -E regex> skips matching keys.
#
# Re-run the same command to check progress. It is safe to repeat.
# Done when every object reports "readable".
#
# Restore time: ARCHIVE_ACCESS 3-5h, DEEP_ARCHIVE_ACCESS up to 12h.
# Intelligent-Tiering has no retrieval fee. Restored objects return to the
# Frequent tier and are archived again after 90 days without access.
#
# Drone TM recipe: restore a project's ODM outputs (orthophotos, DEMs and
# asset zips users view and download), leaving raw imagery and the
# undistorted photo copies (not served to users) archived:
#
#   export AWS_PROFILE=admin
#   export EXCLUDE='/opensfm/undistorted/'
#   P=<project-id>
#   bash unarchive-s3-path.sh dronetm-prod "projects/$P/odm/" \
#     $(aws s3 ls "s3://dronetm-prod/projects/$P/" | grep -oE '[0-9a-f-]{36}/' |
#       sed "s|^|projects/$P/|; s|$|odm/|")
# -------------------------------------------------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: AWS_PROFILE=<profile> $0 <bucket-name> <prefix>..."
  exit 1
fi

BUCKET="$1"
shift
PARALLEL_REQUESTS=32
# Intelligent-Tiering never archives objects smaller than 128 KiB.
MIN_ARCHIVABLE_BYTES=131072
# Text output prints "None" for an empty listing.
SKIP_KEYS="^None\$${EXCLUDE:+|$EXCLUDE}"
LOG_FILE=$(mktemp)
trap 'rm -f "$LOG_FILE"' EXIT

for prefix in "$@"; do
  # An empty prefix would restore the whole bucket.
  if [[ -z "$prefix" ]]; then
    echo "Refusing empty prefix."
    exit 1
  fi
done

echo "========================================="
echo "🪣 Bucket: $BUCKET"
echo "📁 Prefixes: $#"
echo "👔 Profile: ${AWS_PROFILE:-default}"
echo "🚫 Exclude: ${EXCLUDE:-none}"
echo "========================================="

# One call per key: S3 rejects restores of non-archived objects with
# InvalidObjectState, which saves a separate head-object per key.
restore_key() {
  local key="$1" err
  if err=$(aws s3api restore-object --bucket "$BUCKET" --key "$key" \
    --restore-request '{"GlacierJobParameters": {"Tier": "Standard"}}' 2>&1); then
    echo "requested $key"
  elif [[ "$err" == *InvalidObjectState* ]]; then
    echo "readable $key"
  elif [[ "$err" == *RestoreAlreadyInProgress* ]]; then
    echo "restoring $key"
  else
    echo "error $key: $err"
  fi
}
export -f restore_key
export BUCKET

for prefix in "$@"; do
  aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$prefix" \
    --query "Contents[?Size >= \`$MIN_ARCHIVABLE_BYTES\`].Key" --output text |
    tr '\t' '\n' | { grep -vE "$SKIP_KEYS" || true; }
done |
  xargs -d '\n' -r -P "$PARALLEL_REQUESTS" -I {} bash -c 'restore_key "$1"' _ {} |
  tee "$LOG_FILE"

echo
echo "Summary:"
cut -d' ' -f1 "$LOG_FILE" | sort | uniq -c
echo
echo "readable  = available now"
echo "restoring = restore in progress, re-run later to check"
echo "requested = restore started by this run"
echo "error     = unexpected failure, see the line above"
