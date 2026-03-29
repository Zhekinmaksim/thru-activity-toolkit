#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "counter-inc"
require_cmd python3

[[ -n "${PROGRAM_ID:-}" ]] || die "PROGRAM_ID is not set. Run 'just deploy' first."
[[ -n "${COUNTER_ID:-}" ]] || die "COUNTER_ID is not set. Run 'just counter-create' first."

prepare_network_activity "counter increment"

payload="$("${SCRIPT_DIR}/render_counter_payload.py" increment 2)"

log "Incrementing counter ${COUNTER_ID}."
run_cmd_retry "Executing counter increment transaction" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" txn execute --fee 0 --readwrite-accounts "${COUNTER_ID}" "${PROGRAM_ID}" "${payload}"
execute_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Counter increment transaction failed."
fi

increment_signature="$(extract_last_signature "${execute_output}")"
COUNTER_INCREMENT_COUNT="$(( ${COUNTER_INCREMENT_COUNT:-0} + 1 ))"
LAST_TX_SIGNATURE="${increment_signature}"
export COUNTER_INCREMENT_COUNT LAST_TX_SIGNATURE

write_env_file "${STATE_DIR}/counter.env" \
  "LAST_RUN_TAG=${RUN_TAG}" \
  "COUNTER_SEED=${COUNTER_SEED}" \
  "COUNTER_ID=${COUNTER_ID}" \
  "COUNTER_PROGRAM_ID=${COUNTER_PROGRAM_ID:-${PROGRAM_ID}}" \
  "COUNTER_CREATE_PAYLOAD=${COUNTER_CREATE_PAYLOAD:-}" \
  "COUNTER_INCREMENT_PAYLOAD=${payload}" \
  "COUNTER_INCREMENT_COUNT=${COUNTER_INCREMENT_COUNT}" \
  "COUNTER_LAST_INCREMENT_SIGNATURE=${increment_signature}"

log "Updated counter state in ${STATE_DIR}/counter.env."
