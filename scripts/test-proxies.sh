#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "test-proxies"

if [[ ! -f "${PROXIES_FILE}" ]]; then
  die "Proxy list not found at ${PROXIES_FILE}. Copy config/proxies.txt.example to config/proxies.txt first."
fi

mapfile -t proxies < <(read_list_file "${PROXIES_FILE}")
if (( ${#proxies[@]} == 0 )); then
  die "No proxies found in ${PROXIES_FILE}."
fi

printf 'index\tstatus\tproxy\terror\n' > "${PROXY_RESULTS_FILE}"

success_count=0
failure_count=0
index=0

for proxy in "${proxies[@]}"; do
  index="$(( index + 1 ))"
  PROXY_URL="${proxy}"
  apply_proxy_env

  log "Testing proxy ${index}/${#proxies[@]}: ${proxy}"
  rpc_health_check_soft

  if (( RUN_STATUS == 0 )); then
    printf '%s\t%s\t%s\t%s\n' "${index}" "success" "${proxy}" "" >> "${PROXY_RESULTS_FILE}"
    success_count="$(( success_count + 1 ))"
    log "Proxy ${index} passed."
  else
    error_line="$(printf '%s\n' "${RUN_OUTPUT}" | tail -n 1 | tr '\t' ' ' || true)"
    printf '%s\t%s\t%s\t%s\n' "${index}" "failed" "${proxy}" "${error_line}" >> "${PROXY_RESULTS_FILE}"
    failure_count="$(( failure_count + 1 ))"
    warn "Proxy ${index} failed."
  fi
done

unset PROXY_URL
apply_proxy_env

write_env_file "${STATE_DIR}/proxy-test.env" \
  "PROXY_TEST_RUN_TAG=${RUN_TAG}" \
  "PROXY_TEST_TOTAL=${#proxies[@]}" \
  "PROXY_TEST_SUCCESS=${success_count}" \
  "PROXY_TEST_FAILED=${failure_count}" \
  "PROXY_RESULTS_FILE=${PROXY_RESULTS_FILE}"

log "Proxy test summary: ${success_count} passed, ${failure_count} failed."
log "Saved proxy results to ${PROXY_RESULTS_FILE}."
