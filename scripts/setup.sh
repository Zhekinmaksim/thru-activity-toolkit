#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "setup"
require_cmd cargo
require_cmd python3
require_cmd make

if ! command -v buf >/dev/null 2>&1; then
  warn "Buf CLI is not installed. The official guide lists it as a prerequisite."
fi

FEE_PAYER="$(ensure_account_alias_prompt)"
export FEE_PAYER
ACCOUNT_ALIAS="${FEE_PAYER}"
export ACCOUNT_ALIAS

ensure_rpc_base_url
rpc_health_check

run_cmd_capture "Listing key aliases" "${THRU_BIN}" keys list
key_list_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Unable to list local key aliases."
fi

if ! grep -Eq "(^|[[:space:]])${FEE_PAYER}($|[[:space:]])" <<<"${key_list_output}"; then
  log "Generating key alias ${FEE_PAYER}."
  run_cmd_capture "Generating key alias ${FEE_PAYER}" "${THRU_BIN}" keys generate "${FEE_PAYER}"
  if (( RUN_STATUS != 0 )); then
    die "Key generation failed."
  fi
else
  log "Key alias ${FEE_PAYER} already exists."
fi

log "Creating on-chain account for ${FEE_PAYER}."
run_cmd_retry "Creating on-chain account" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" account create "${FEE_PAYER}"
account_output="${RUN_OUTPUT}"
account_status="${RUN_STATUS}"

if (( account_status != 0 )); then
  provisional_public_key="$(extract_label_value "${account_output}" "Public Key")"
  if [[ -z "${provisional_public_key}" ]]; then
    provisional_public_key="$(extract_label_value "${account_output}" "Account public key")"
  fi

  if grep -Eqi 'exist|NONCE_TOO_LOW' <<<"${account_output}" && [[ -n "${provisional_public_key}" ]]; then
    warn "Account creation returned a reusable-state error; verifying whether the account already exists."
    run_cmd_capture "Checking existing on-chain account" "${THRU_BIN}" account info "${provisional_public_key}"
    if (( RUN_STATUS == 0 )); then
      account_output="${account_output}"$'\n'"${RUN_OUTPUT}"
      account_status=0
      warn "Account already exists on-chain; continuing."
    else
      die "Account creation failed and the account could not be verified on-chain."
    fi
  elif grep -qi 'exist' <<<"${account_output}"; then
    warn "Account may already exist; continuing."
  else
    die "Account creation failed."
  fi
fi

LAST_TX_SIGNATURE="$(extract_last_signature "${account_output}")"
export LAST_TX_SIGNATURE

account_public_key="$(extract_label_value "${account_output}" "Public Key")"
if [[ -z "${account_public_key}" ]]; then
  account_public_key="$(extract_label_value "${account_output}" "Account public key")"
fi

if [[ -z "${account_public_key}" ]]; then
  warn "Could not parse a public key from '${THRU_BIN} account create ${FEE_PAYER}'."
fi

ACCOUNT_PUBLIC_KEY="${account_public_key}"
export ACCOUNT_PUBLIC_KEY

write_env_file "${STATE_DIR}/account.env" \
  "ACCOUNT_ALIAS=${FEE_PAYER}" \
  "ACCOUNT_PUBLIC_KEY=${account_public_key}"

log "Saved account details to ${STATE_DIR}/account.env."

if [[ ! -d "${HOME}/.thru/sdk/toolchain" ]]; then
  log "Installing the Thru RISC-V toolchain."
  run_cmd_capture "Installing Thru toolchain" "${THRU_BIN}" dev toolchain install
  if (( RUN_STATUS != 0 )); then
    die "Toolchain installation failed."
  fi
else
  log "Thru toolchain already exists at ${HOME}/.thru/sdk/toolchain."
fi

if [[ ! -d "${HOME}/.thru/sdk/c/thru-sdk" ]]; then
  log "Installing the Thru C SDK."
  run_cmd_capture "Installing Thru C SDK" "${THRU_BIN}" dev sdk install c
  if (( RUN_STATUS != 0 )); then
    die "C SDK installation failed."
  fi
else
  log "Thru C SDK already exists at ${HOME}/.thru/sdk/c/thru-sdk."
fi

request_faucet
