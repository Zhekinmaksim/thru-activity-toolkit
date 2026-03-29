#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "deploy"

binary_path="${COUNTER_PROGRAM_DIR}/build/thruvm/bin/tn_counter_program_c.bin"
run_tag="${RUN_TAG}"
seed_suffix="$(short_tag "${run_tag}")"
program_seed="$(make_ascii_seed "${PROGRAM_SEED_BASE}" "${seed_suffix}")"

if [[ ! -f "${binary_path}" ]]; then
  die "Program binary not found at ${binary_path}. Run 'just build' first."
fi

if resume_enabled && [[ -n "${PROGRAM_ID:-}" && -n "${PROGRAM_SEED:-}" ]]; then
  log "Resume enabled and a deployed program already exists in state (${PROGRAM_ID}). Set FORCE_RUN=1 to deploy a new one."
  exit 0
fi

prepare_network_activity "program deployment"

log "Deploying program with seed ${program_seed}."
run_cmd_retry "Deploying program" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" program create "${program_seed}" "${binary_path}"
deploy_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Program deployment failed."
fi

program_id="$(extract_label_value "${deploy_output}" "Program account")"
program_meta="$(extract_label_value "${deploy_output}" "Meta account")"
program_signature="$(extract_last_signature "${deploy_output}")"

[[ -n "${program_id}" ]] || die "Unable to parse the deployed program account."

PROGRAM_SEED="${program_seed}"
PROGRAM_ID="${program_id}"
PROGRAM_META="${program_meta}"
PROGRAM_BIN="${binary_path}"
LAST_TX_SIGNATURE="${program_signature}"
export PROGRAM_SEED PROGRAM_ID PROGRAM_META PROGRAM_BIN LAST_TX_SIGNATURE

write_env_file "${STATE_DIR}/program.env" \
  "LAST_RUN_TAG=${run_tag}" \
  "PROGRAM_SEED=${program_seed}" \
  "PROGRAM_ID=${program_id}" \
  "PROGRAM_META=${program_meta}" \
  "PROGRAM_BIN=${binary_path}" \
  "PROGRAM_CREATE_SIGNATURE=${program_signature}"

log "Saved deployed program details to ${STATE_DIR}/program.env."
