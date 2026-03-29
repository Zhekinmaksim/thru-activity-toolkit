#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
start_run_logging "build"
require_cmd make

[[ -d "${COUNTER_PROGRAM_DIR}" ]] || die "Counter program directory not found: ${COUNTER_PROGRAM_DIR}"

log "Building the sample Thru counter program."
run_cmd_capture "Building counter program" make -C "${COUNTER_PROGRAM_DIR}"
if (( RUN_STATUS != 0 )); then
  die "Build failed."
fi
