#!/usr/bin/env bash
set -euo pipefail
# -------------------------------------------------------------
# Prove WAL archiving works, per CloudNativePG cluster.
#
# A base backup succeeding proves nothing (separate paths, base/ vs wals/), and
# an idle database archives nothing at all - so status reads green while
# archiving is broken. Forcing a segment and watching it land is the only proof.
#
# Usage:
#   bash verify-cnpg-backups.sh                 # audit all (wraps kubectl cnpg status)
#   bash verify-cnpg-backups.sh <cluster-name>  # force a real archive, one cluster
# -------------------------------------------------------------

NS="${NS:-postgres}"
WAL_WAIT="${WAL_WAIT:-30}"
# Forcing a switch consumes WAL space. Refuse if the volume is already tight.
MAX_WAL_PCT="${MAX_WAL_PCT:-85}"

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; OFF=$'\e[0m'

# ---------- audit mode: no argument ----------
if [[ $# -eq 0 ]]; then
  echo "${BOLD}Continuous backup status, all clusters in ${NS}${OFF}"
  echo
  for C in $(kubectl get cluster -n "$NS" -o jsonpath='{.items[*].metadata.name}'); do
    echo "${BOLD}=== ${C}${OFF}"
    kubectl cnpg status "$C" -n "$NS" 2>/dev/null \
      | grep -A6 -i "continuous backup" || echo "  ${RED}could not read status${OFF}"
    echo
  done
  echo "${YELLOW}This is a passive read.${OFF} A green archiver on an idle database proves"
  echo "nothing. Re-run as: $0 <cluster-name>  to force a real upload."
  exit 0
fi

# ---------- active test: one named cluster ----------
CLUSTER="$1"

PRIMARY=$(kubectl get cluster -n "$NS" "$CLUSTER" -o jsonpath='{.status.currentPrimary}')
PHASE=$(kubectl get cluster -n "$NS" "$CLUSTER" -o jsonpath='{.status.phase}')
[[ -z "$PRIMARY" ]] && { echo "${RED}No primary elected for ${CLUSTER}${OFF}"; exit 1; }

echo "${BOLD}${NS}/${CLUSTER}${OFF}  primary=${PRIMARY}  phase=${PHASE}"

q() { kubectl exec -n "$NS" "$PRIMARY" -c postgres -- psql -U postgres -d postgres -tAF$'\t' -c "$1"; }

# Switching on a nearly-full volume worsens the exact failure being tested for.
DATADIR=$(q "select setting from pg_settings where name='data_directory';")
WAL_PCT=$(kubectl exec -n "$NS" "$PRIMARY" -c postgres -- \
  df -P "${DATADIR}/pg_wal" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
echo "  WAL volume ${WAL_PCT}% used"
if [[ "$WAL_PCT" -ge "$MAX_WAL_PCT" ]]; then
  echo "${RED}REFUSING${OFF} - WAL volume at ${WAL_PCT}% (limit ${MAX_WAL_PCT}%)."
  echo "Forcing a switch here consumes more WAL and accelerates the outage."
  echo "Expand the volume first, then re-run. Override with MAX_WAL_PCT=<n> only"
  echo "if you know the volume has headroom."
  exit 1
fi

BEFORE=$(q "select coalesce(last_archived_wal,'none'), failed_count from pg_stat_archiver;")
IFS=$'\t' read -r B_WAL B_FAIL <<<"$BEFORE"
echo "  before: archived=${B_WAL} failures=${B_FAIL}"

# One XID so the switch has something to archive. No schema, no rows.
q "select pg_switch_wal();"       >/dev/null
q "select pg_current_xact_id();"  >/dev/null
q "select pg_switch_wal();"       >/dev/null

echo "  waiting ${WAL_WAIT}s for upload..."
sleep "$WAL_WAIT"

AFTER=$(q "select coalesce(last_archived_wal,'none'), failed_count from pg_stat_archiver;")
IFS=$'\t' read -r A_WAL A_FAIL <<<"$AFTER"
echo "  after:  archived=${A_WAL} failures=${A_FAIL}"

if [[ "$A_FAIL" -gt "$B_FAIL" ]]; then
  echo "${RED}FAIL${OFF} archiving errored during the test. The S3 error is in the sidecar:"
  echo "  kubectl logs -n ${NS} ${PRIMARY} -c plugin-barman-cloud --tail=50"
  exit 1
elif [[ "$A_WAL" == "$B_WAL" ]]; then
  echo "${RED}FAIL${OFF} nothing archived in ${WAL_WAIT}s - stalled, not erroring."
  echo "Check the WAL volume and for inactive replication slots pinning segments."
  exit 1
fi

echo "${GREEN}PASS${OFF} ${B_WAL} -> ${A_WAL} reached S3"
