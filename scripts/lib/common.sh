#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${ROOT_DIR}/config"
STATE_DIR="${ROOT_DIR}/state"
LOG_DIR="${ROOT_DIR}/logs"
ACCOUNT_FILE="${CONFIG_DIR}/account.txt"
PROXY_FILE="${CONFIG_DIR}/proxy.txt"
PROXIES_FILE="${CONFIG_DIR}/proxies.txt"
CURRENT_STATE_FILE="${STATE_DIR}/current.env"
CURRENT_STATE_TEXT_FILE="${STATE_DIR}/current.txt"
LAST_ACTION_FILE="${STATE_DIR}/last-action.env"
RUN_HISTORY_FILE="${STATE_DIR}/history.tsv"
PROXY_RESULTS_FILE="${STATE_DIR}/proxy-results.tsv"

RUN_OUTPUT=""
RUN_STATUS=0

log() {
  printf '[thru] %s\n' "$*"
  if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
    printf '[thru] %s\n' "$*" >> "${CURRENT_LOG_FILE}"
  fi
}

warn() {
  printf '[thru][warn] %s\n' "$*" >&2
  if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
    printf '[thru][warn] %s\n' "$*" >> "${CURRENT_LOG_FILE}"
  fi
}

die() {
  printf '[thru][error] %s\n' "$*" >&2
  if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
    printf '[thru][error] %s\n' "$*" >> "${CURRENT_LOG_FILE}"
  fi
  exit 1
}

load_env_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    # shellcheck disable=SC1090
    source "${file}"
  fi
}

read_single_value_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    awk '
      /^[[:space:]]*#/ {next}
      /^[[:space:]]*$/ {next}
      {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "${file}"
  fi
}

bootstrap_env() {
  mkdir -p "${STATE_DIR}" "${LOG_DIR}"

  load_env_file "${CONFIG_DIR}/app.env"
  load_env_file "${CONFIG_DIR}/keys.env"
  load_env_file "${STATE_DIR}/account.env"
  load_env_file "${LAST_ACTION_FILE}"
  load_env_file "${STATE_DIR}/program.env"
  load_env_file "${STATE_DIR}/counter.env"
  load_env_file "${STATE_DIR}/token.env"
  load_env_file "${STATE_DIR}/nameservice.env"

  if [[ -f "${ACCOUNT_FILE}" ]]; then
    FEE_PAYER="$(read_single_value_file "${ACCOUNT_FILE}")"
  fi

  if [[ -f "${PROXY_FILE}" ]]; then
    PROXY_URL="$(read_single_value_file "${PROXY_FILE}")"
  fi

  : "${RPC_BASE_URL:=https://grpc.alphanet.thruput.org}"
  : "${FEE_PAYER:=default}"
  : "${FAUCET_AMOUNT:=1000}"
  : "${FAUCET_STRICT:=0}"
  : "${RESUME_ENABLED:=1}"
  : "${FORCE_RUN:=0}"
  : "${NETWORK_RETRY_ATTEMPTS:=3}"
  : "${NETWORK_RETRY_SLEEP:=5}"
  : "${RPC_HEALTHCHECK_ENABLED:=1}"
  : "${RPC_HEALTHCHECK_ATTEMPTS:=3}"
  : "${RPC_HEALTHCHECK_SLEEP:=3}"
  : "${PROXY_TEST_RETRY_ATTEMPTS:=${RPC_HEALTHCHECK_ATTEMPTS}}"
  : "${PROXY_TEST_RETRY_SLEEP:=${RPC_HEALTHCHECK_SLEEP}}"
  : "${ACTIVITY_DELAY_ENABLED:=1}"
  : "${ACTIVITY_DELAY_MIN:=30}"
  : "${ACTIVITY_DELAY_MAX:=60}"
  : "${COUNTER_PROGRAM_DIR:=${ROOT_DIR}/counter-program}"
  : "${PROGRAM_SEED_BASE:=mycounter}"
  : "${COUNTER_SEED_BASE:=count}"
  : "${TOKEN_TICKER_BASE:=TST}"
  : "${TOKEN_DECIMALS:=9}"
  : "${TOKEN_MINT_SEED_BASE:=mint}"
  : "${TOKEN_ACCOUNT_SEED_BASE:=acct}"
  : "${TOKEN_MINT_AMOUNT:=1000000000}"
  : "${NAMESERVICE_MODE:=root}"
  : "${NAMESERVICE_ROOT_BASE:=lab}"
  : "${NAMESERVICE_SUBDOMAIN_BASE:=dev}"
  : "${NAMESERVICE_RECORD_KEY:=github}"
  : "${NAMESERVICE_RECORD_VALUE_TEMPLATE:=https://example.invalid/__RUN_TAG__}"
  : "${MINT_AUTHORITY:=${FEE_PAYER}}"
  : "${TOKEN_OWNER:=${FEE_PAYER}}"
  : "${TOKEN_FREEZE_AUTHORITY:=${FEE_PAYER}}"
  : "${NAMESERVICE_OWNER:=${FEE_PAYER}}"
  : "${NAMESERVICE_AUTHORITY:=${FEE_PAYER}}"
  : "${PROXY_URL:=}"

  apply_proxy_env
}

resume_enabled() {
  [[ "${RESUME_ENABLED}" == "1" && "${FORCE_RUN}" != "1" ]]
}

ensure_account_alias_prompt() {
  local alias_value=""

  alias_value="$(read_single_value_file "${ACCOUNT_FILE}" || true)"
  if [[ -n "${alias_value}" ]]; then
    printf '%s\n' "${alias_value}"
    return
  fi

  if [[ ! -t 0 ]]; then
    printf '%s\n' "${FEE_PAYER:-default}"
    return
  fi

  printf 'Enter your thru-cli key alias [default]: ' >&2
  read -r alias_value
  alias_value="${alias_value:-default}"

  mkdir -p "${CONFIG_DIR}"
  printf '%s\n' "${alias_value}" > "${ACCOUNT_FILE}"
  log "Saved key alias to ${ACCOUNT_FILE}."
  printf '%s\n' "${alias_value}"
}

detect_thru_bin() {
  if command -v thru-cli >/dev/null 2>&1; then
    THRU_BIN="thru-cli"
  elif command -v thru >/dev/null 2>&1; then
    THRU_BIN="thru"
  else
    die "Neither thru-cli nor thru is installed. Follow the official Setup the DevKit guide first."
  fi
  export THRU_BIN
}

apply_proxy_env() {
  if [[ -n "${PROXY_URL:-}" ]]; then
    export HTTP_PROXY="${PROXY_URL}"
    export HTTPS_PROXY="${PROXY_URL}"
    export ALL_PROXY="${PROXY_URL}"
  else
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy 2>/dev/null || true
  fi
}

quote_command() {
  local quoted=""
  local part

  for part in "$@"; do
    printf -v part '%q' "${part}"
    quoted+="${part} "
  done

  printf '%s\n' "${quoted% }"
}

start_run_logging() {
  local step="$1"
  local timestamp_file

  RUN_TAG="${RUN_TAG:-$(make_run_tag)}"
  CURRENT_STEP="${step}"
  CURRENT_RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  LAST_TX_SIGNATURE=""
  timestamp_file="$(date -u +%Y%m%dT%H%M%SZ)"
  CURRENT_LOG_FILE="${LOG_DIR}/${timestamp_file}_${step}_${RUN_TAG}.log"
  export RUN_TAG CURRENT_STEP CURRENT_RUN_STARTED_AT CURRENT_LOG_FILE LAST_TX_SIGNATURE

  touch "${CURRENT_LOG_FILE}"
  trap 'finalize_run $?' EXIT

  log "Started ${CURRENT_STEP}."
  log "Run tag: ${RUN_TAG}"
  log "Log file: ${CURRENT_LOG_FILE}"
}

require_cmd() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || die "Required command not found: ${name}"
}

is_ta_address() {
  [[ "$1" =~ ^ta[[:alnum:]_-]+$ ]]
}

is_hex64() {
  [[ "$1" =~ ^[0-9a-fA-F]{64}$ ]]
}

resolve_single_account_identity() {
  local value="$1"

  if [[ -z "${value}" ]]; then
    printf '\n'
    return
  fi

  if is_ta_address "${value}" || is_hex64 "${value}"; then
    printf '%s\n' "${value}"
    return
  fi

  if [[ "${value}" == "${ACCOUNT_ALIAS:-}" || "${value}" == "${FEE_PAYER:-}" ]]; then
    if [[ -n "${ACCOUNT_PUBLIC_KEY:-}" ]]; then
      printf '%s\n' "${ACCOUNT_PUBLIC_KEY}"
      return
    fi
  fi

  printf '%s\n' "${value}"
}

ensure_rpc_base_url() {
  local file="${HOME}/.thru/cli/config.yaml"
  local tmp

  mkdir -p "$(dirname "${file}")"

  if [[ -f "${file}" ]] && grep -q '^rpc_base_url:' "${file}"; then
    tmp="${file}.tmp.$$"
    awk -v value="${RPC_BASE_URL}" '
      BEGIN {done=0}
      /^rpc_base_url:/ {print "rpc_base_url: " value; done=1; next}
      {print}
      END {if (!done) print "rpc_base_url: " value}
    ' "${file}" > "${tmp}"
    mv "${tmp}" "${file}"
  else
    printf 'rpc_base_url: %s\n' "${RPC_BASE_URL}" >> "${file}"
  fi

  log "Configured rpc_base_url in ${file}"
}

make_run_tag() {
  local stamp rand
  if [[ -n "${RUN_TAG:-}" ]]; then
    printf '%s\n' "${RUN_TAG}"
    return
  fi

  stamp="$(date -u +%Y%m%d%H%M%S)"
  rand="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(2))
PY
)"
  printf '%s-%s\n' "${stamp}" "${rand}"
}

short_tag() {
  printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-8
}

make_ascii_seed() {
  local base="$1"
  local suffix="$2"
  printf '%s' "${base}_${suffix}" | tr -cd '[:alnum:]_-' | cut -c1-32
}

hash_to_hex64() {
  local value="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${value}" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "${value}" | sha256sum | awk '{print $1}'
  fi
}

make_token_ticker() {
  local base suffix
  base="$(printf '%s' "${1}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9' | cut -c1-5)"
  suffix="$(printf '%s' "${2}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9' | cut -c1-3)"
  printf '%s%s\n' "${base}" "${suffix}" | cut -c1-8
}

sleep_random_delay() {
  local min="${1:-${ACTIVITY_DELAY_MIN}}"
  local max="${2:-${ACTIVITY_DELAY_MAX}}"
  local seconds

  if [[ "${ACTIVITY_DELAY_ENABLED}" != "1" ]]; then
    return
  fi

  if (( max < min )); then
    seconds="${min}"
  elif (( max == min )); then
    seconds="${min}"
  else
    seconds="$(( RANDOM % (max - min + 1) + min ))"
  fi

  log "Waiting ${seconds}s before the network activity."
  sleep "${seconds}"
}

run_cmd_capture() {
  local label="$1"
  shift
  local output status

  log "${label}"
  log "Command: $(quote_command "$@")"

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  RUN_OUTPUT="${output}"
  RUN_STATUS="${status}"

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}"
    if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
      printf '%s\n' "${output}" >> "${CURRENT_LOG_FILE}"
    fi
  fi

  return 0
}

run_cmd_retry() {
  local label="$1"
  local attempts="$2"
  local sleep_seconds="$3"
  shift 3
  local attempt

  for (( attempt=1; attempt<=attempts; attempt++ )); do
    run_cmd_capture "${label} (attempt ${attempt}/${attempts})" "$@"
    if (( RUN_STATUS == 0 )); then
      return 0
    fi

    warn "${label} failed with status ${RUN_STATUS}."
    if (( attempt < attempts )); then
      log "Retrying in ${sleep_seconds}s."
      sleep "${sleep_seconds}"
    fi
  done

  return 0
}

rpc_health_check() {
  if [[ "${RPC_HEALTHCHECK_ENABLED}" != "1" ]]; then
    log "RPC health check skipped."
    return
  fi

  if [[ "${THRU_BIN}" == "thru-cli" ]]; then
    run_cmd_retry "RPC health check" "${RPC_HEALTHCHECK_ATTEMPTS}" "${RPC_HEALTHCHECK_SLEEP}" \
      "${THRU_BIN}" --json getversion
    if (( RUN_STATUS != 0 )); then
      run_cmd_retry "RPC health check fallback" "${RPC_HEALTHCHECK_ATTEMPTS}" "${RPC_HEALTHCHECK_SLEEP}" \
        "${THRU_BIN}" getversion
    fi
  else
    run_cmd_retry "RPC health check" "${RPC_HEALTHCHECK_ATTEMPTS}" "${RPC_HEALTHCHECK_SLEEP}" \
      "${THRU_BIN}" rpc getversion
    if (( RUN_STATUS != 0 )); then
      run_cmd_retry "RPC health check fallback" "${RPC_HEALTHCHECK_ATTEMPTS}" "${RPC_HEALTHCHECK_SLEEP}" \
        "${THRU_BIN}" getversion
    fi
  fi

  if (( RUN_STATUS != 0 )); then
    die "RPC health check failed."
  fi
}

rpc_health_check_soft() {
  if [[ "${THRU_BIN}" == "thru-cli" ]]; then
    run_cmd_retry "RPC health check" "${PROXY_TEST_RETRY_ATTEMPTS}" "${PROXY_TEST_RETRY_SLEEP}" \
      "${THRU_BIN}" --json getversion
    if (( RUN_STATUS != 0 )); then
      run_cmd_retry "RPC health check fallback" "${PROXY_TEST_RETRY_ATTEMPTS}" "${PROXY_TEST_RETRY_SLEEP}" \
        "${THRU_BIN}" getversion
    fi
  else
    run_cmd_retry "RPC health check" "${PROXY_TEST_RETRY_ATTEMPTS}" "${PROXY_TEST_RETRY_SLEEP}" \
      "${THRU_BIN}" rpc getversion
    if (( RUN_STATUS != 0 )); then
      run_cmd_retry "RPC health check fallback" "${PROXY_TEST_RETRY_ATTEMPTS}" "${PROXY_TEST_RETRY_SLEEP}" \
        "${THRU_BIN}" getversion
    fi
  fi
}

request_faucet() {
  log "Requesting faucet tokens for ${FEE_PAYER}."
  run_cmd_retry "Faucet request" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
    "${THRU_BIN}" faucet withdraw "${FEE_PAYER}" "${FAUCET_AMOUNT}"

  if (( RUN_STATUS != 0 )); then
    if [[ "${FAUCET_STRICT}" == "1" ]]; then
      die "Faucet request failed."
    fi
    warn "Faucet request failed; continuing because FAUCET_STRICT=${FAUCET_STRICT}."
  fi
}

prepare_network_activity() {
  local label="$1"
  log "Preparing network activity: ${label}"
  rpc_health_check
  request_faucet
  sleep_random_delay
}

extract_label_value() {
  local text="$1"
  local label="$2"
  printf '%s\n' "${text}" | awk -v label="${label}" '
    {
      marker = label ": "
      pos = index($0, marker)
      if (pos > 0) {
        print substr($0, pos + length(marker))
      }
    }
  ' | tail -n 1
}

extract_last_account() {
  printf '%s\n' "$1" | grep -Eo 'ta[[:alnum:]_-]+' | tail -n 1 || true
}

extract_last_signature() {
  printf '%s\n' "$1" | grep -Eo 'ts[[:alnum:]_-]+' | tail -n 1 || true
}

read_list_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    awk '
      /^[[:space:]]*#/ {next}
      /^[[:space:]]*$/ {next}
      {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
      }
    ' "${file}"
  fi
}

write_env_file() {
  local file="$1"
  shift
  local entry key value

  : > "${file}"
  for entry in "$@"; do
    key="${entry%%=*}"
    value="${entry#*=}"
    printf '%s=%q\n' "${key}" "${value}" >> "${file}"
  done
}

refresh_current_state() {
  write_env_file "${CURRENT_STATE_FILE}" \
    "ACCOUNT_ALIAS=${ACCOUNT_ALIAS:-${FEE_PAYER:-}}" \
    "ACCOUNT_PUBLIC_KEY=${ACCOUNT_PUBLIC_KEY:-}" \
    "PROGRAM_ID=${PROGRAM_ID:-}" \
    "PROGRAM_SEED=${PROGRAM_SEED:-}" \
    "COUNTER_ID=${COUNTER_ID:-}" \
    "COUNTER_SEED=${COUNTER_SEED:-}" \
    "COUNTER_INCREMENT_COUNT=${COUNTER_INCREMENT_COUNT:-0}" \
    "TOKEN_TICKER=${TOKEN_TICKER:-}" \
    "TOKEN_MINT_ADDRESS=${TOKEN_MINT_ADDRESS:-}" \
    "TOKEN_ACCOUNT_ADDRESS=${TOKEN_ACCOUNT_ADDRESS:-}" \
    "NAMESERVICE_ROOT_NAME=${NAMESERVICE_ROOT_NAME:-}" \
    "NAMESERVICE_DOMAIN_ACCOUNT=${NAMESERVICE_DOMAIN_ACCOUNT:-}" \
    "LAST_STEP=${CURRENT_STEP:-${LAST_STEP:-}}" \
    "LAST_STATUS=${LAST_STATUS:-}" \
    "LAST_RUN_TAG=${RUN_TAG:-${LAST_RUN_TAG:-}}" \
    "LAST_LOG_FILE=${CURRENT_LOG_FILE:-${LAST_LOG_FILE:-}}" \
    "LAST_TX_SIGNATURE=${LAST_TX_SIGNATURE:-}" \
    "LAST_UPDATED_AT=${LAST_UPDATED_AT:-}"

  cat > "${CURRENT_STATE_TEXT_FILE}" <<EOF
Last Step: ${CURRENT_STEP:-${LAST_STEP:-}}
Last Status: ${LAST_STATUS:-}
Last Run Tag: ${RUN_TAG:-${LAST_RUN_TAG:-}}
Last Log File: ${CURRENT_LOG_FILE:-${LAST_LOG_FILE:-}}
Last Tx Signature: ${LAST_TX_SIGNATURE:-}
Last Updated At: ${LAST_UPDATED_AT:-}

Account Alias: ${ACCOUNT_ALIAS:-${FEE_PAYER:-}}
Account Public Key: ${ACCOUNT_PUBLIC_KEY:-}

Program ID: ${PROGRAM_ID:-}
Program Seed: ${PROGRAM_SEED:-}

Counter ID: ${COUNTER_ID:-}
Counter Seed: ${COUNTER_SEED:-}
Counter Increment Count: ${COUNTER_INCREMENT_COUNT:-0}

Token Ticker: ${TOKEN_TICKER:-}
Token Mint Address: ${TOKEN_MINT_ADDRESS:-}
Token Account Address: ${TOKEN_ACCOUNT_ADDRESS:-}

Nameservice Root: ${NAMESERVICE_ROOT_NAME:-}
Nameservice Domain Account: ${NAMESERVICE_DOMAIN_ACCOUNT:-}
EOF
}

append_run_history() {
  if [[ ! -f "${RUN_HISTORY_FILE}" ]]; then
    printf 'started_at\tstep\trun_tag\tstatus\tlog_file\ttx_signature\n' > "${RUN_HISTORY_FILE}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${CURRENT_RUN_STARTED_AT:-}" \
    "${CURRENT_STEP:-}" \
    "${RUN_TAG:-}" \
    "${LAST_STATUS:-}" \
    "${CURRENT_LOG_FILE:-}" \
    "${LAST_TX_SIGNATURE:-}" >> "${RUN_HISTORY_FILE}"
}

finalize_run() {
  local exit_code="${1:-0}"

  set +e
  LAST_UPDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if (( exit_code == 0 )); then
    LAST_STATUS="success"
  else
    LAST_STATUS="failed"
  fi
  export LAST_STATUS LAST_UPDATED_AT

  write_env_file "${LAST_ACTION_FILE}" \
    "LAST_STEP=${CURRENT_STEP:-}" \
    "LAST_STATUS=${LAST_STATUS:-}" \
    "LAST_RUN_TAG=${RUN_TAG:-}" \
    "LAST_LOG_FILE=${CURRENT_LOG_FILE:-}" \
    "LAST_TX_SIGNATURE=${LAST_TX_SIGNATURE:-}" \
    "LAST_UPDATED_AT=${LAST_UPDATED_AT:-}"

  refresh_current_state
  append_run_history

  if (( exit_code == 0 )); then
    log "Completed ${CURRENT_STEP:-step} successfully."
  else
    warn "${CURRENT_STEP:-step} failed with exit code ${exit_code}."
  fi
}
