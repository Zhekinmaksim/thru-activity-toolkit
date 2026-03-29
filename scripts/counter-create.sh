#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "counter-create"
require_cmd python3

[[ -n "${PROGRAM_ID:-}" ]] || die "PROGRAM_ID is not set. Run 'just deploy' first."

run_tag="${RUN_TAG}"
seed_suffix="$(short_tag "${run_tag}")"
counter_seed="$(make_ascii_seed "${COUNTER_SEED_BASE}" "${seed_suffix}")"

if resume_enabled && [[ -n "${COUNTER_ID:-}" && "${COUNTER_PROGRAM_ID:-${PROGRAM_ID}}" == "${PROGRAM_ID}" ]]; then
  log "Resume enabled and a counter already exists in state (${COUNTER_ID}). Set FORCE_RUN=1 to create a new one."
  exit 0
fi

prepare_network_activity "counter creation"

log "Deriving counter account for seed ${counter_seed}."
run_cmd_retry "Deriving counter account" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" program derive-address "${PROGRAM_ID}" "${counter_seed}"
derive_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Unable to derive the counter address."
fi
counter_id="$(extract_label_value "${derive_output}" "Derived Address")"

[[ -n "${counter_id}" ]] || die "Unable to parse the derived counter address."

log "Requesting state proof for ${counter_id}."
run_cmd_retry "Creating state proof" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" txn make-state-proof creating "${counter_id}"
proof_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "State proof request failed."
fi
proof_hex="$(extract_label_value "${proof_output}" "Proof Data (hex)")"

[[ -n "${proof_hex}" ]] || die "Unable to parse the proof hex."

payload="$("${SCRIPT_DIR}/render_counter_payload.py" create 2 "${counter_seed}" "${proof_hex}")"

log "Creating counter account ${counter_id}."
run_cmd_retry "Executing counter create transaction" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" txn execute --fee 0 --readwrite-accounts "${counter_id}" "${PROGRAM_ID}" "${payload}"
execute_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Counter creation transaction failed."
fi
counter_signature="$(extract_last_signature "${execute_output}")"

COUNTER_SEED="${counter_seed}"
COUNTER_ID="${counter_id}"
COUNTER_PROGRAM_ID="${PROGRAM_ID}"
COUNTER_CREATE_PAYLOAD="${payload}"
LAST_TX_SIGNATURE="${counter_signature}"
export COUNTER_SEED COUNTER_ID COUNTER_PROGRAM_ID COUNTER_CREATE_PAYLOAD LAST_TX_SIGNATURE

write_env_file "${STATE_DIR}/counter.env" \
  "LAST_RUN_TAG=${run_tag}" \
  "COUNTER_SEED=${counter_seed}" \
  "COUNTER_ID=${counter_id}" \
  "COUNTER_PROGRAM_ID=${PROGRAM_ID}" \
  "COUNTER_CREATE_PAYLOAD=${payload}" \
  "COUNTER_CREATE_SIGNATURE=${counter_signature}" \
  "COUNTER_INCREMENT_COUNT=${COUNTER_INCREMENT_COUNT:-0}"

log "Saved counter details to ${STATE_DIR}/counter.env."
