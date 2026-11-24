#!/usr/bin/env bash
set -euo pipefail
# -------------------------------------------------------------
# Restore S3 Intelligent-Tiering archived objects under a prefix
# Usage:
#   bash unarchive-s3-path.sh <bucket-name> <prefix> [profile-name]
#
# Example (one Drone TM task, or drop the task id for a whole project):
#   bash unarchive-s3-path.sh dronetm-prod projects/<project-id>/<task-id>/
#
# Re-run the same command to check progress. It only requests restores for
# objects still archived, so it is safe to run repeatedly. Done when every
# object reports "readable".
#
# Restore time: ARCHIVE_ACCESS 3-5h, DEEP_ARCHIVE_ACCESS up to 12h.
# Intelligent-Tiering has no retrieval fee. Restored objects return to the
# Frequent tier and are archived again after 90 days without access.
# -------------------------------------------------------------
if [[ $# -lt 2 || -z "$2" ]]; then
  echo "Usage: $0 <bucket-name> <prefix> [profile-name]"
  exit 1
fi

BUCKET="$1"
PREFIX="$2"
PROFILE="${3:-admin}"
PARALLEL_REQUESTS=16
# Intelligent-Tiering never archives objects smaller than 128 KiB.
MIN_ARCHIVABLE_BYTES=131072

echo "========================================="
echo "🪣 Bucket: $BUCKET"
echo "📁 Prefix: $PREFIX"
echo "👔 Profile: $PROFILE"
echo "========================================="

# Prints one status per key: readable, restoring or requested.
restore_key() {
  local key="$1" archive_status restore_status
  IFS=$'\t' read -r archive_status restore_status < <(
    aws s3api head-object --bucket "$BUCKET" --key "$key" --profile "$PROFILE" \
      --query '[ArchiveStatus, Restore]' --output text
  )

  if [[ "$archive_status" == "None" ]]; then
    echo "readable"
  elif [[ "$restore_status" == *'ongoing-request="true"'* ]]; then
    echo "restoring"
  else
    # Intelligent-Tiering restores take no Days value, unlike Glacier.
    aws s3api restore-object --bucket "$BUCKET" --key "$key" --profile "$PROFILE" \
      --restore-request '{"GlacierJobParameters": {"Tier": "Standard"}}'
    echo "requested"
  fi
}
export -f restore_key
export BUCKET PROFILE

aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$PREFIX" --profile "$PROFILE" \
  --query "Contents[?Size >= \`$MIN_ARCHIVABLE_BYTES\`].Key" --output text |
  tr '\t' '\n' |
  { grep -v '^None$' || true; } |
  xargs -d '\n' -r -P "$PARALLEL_REQUESTS" -I {} bash -c 'restore_key "$1"' _ {} |
  sort | uniq -c

echo
echo "readable  = available now"
echo "restoring = restore in progress, re-run later to check"
echo "requested = restore started by this run"
