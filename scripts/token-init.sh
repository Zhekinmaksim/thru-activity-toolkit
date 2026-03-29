#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "token-init"

run_tag="${RUN_TAG}"
seed_suffix="$(short_tag "${run_tag}")"
ticker="$(make_token_ticker "${TOKEN_TICKER_BASE}" "${seed_suffix}")"
mint_seed="$(hash_to_hex64 "${TOKEN_MINT_SEED_BASE}-${run_tag}")"
account_seed="$(hash_to_hex64 "${TOKEN_ACCOUNT_SEED_BASE}-${run_tag}")"
creator_address="$(resolve_single_account_identity "${FEE_PAYER}")"
mint_authority_address="$(resolve_single_account_identity "${MINT_AUTHORITY}")"
freeze_authority_address="$(resolve_single_account_identity "${TOKEN_FREEZE_AUTHORITY}")"
token_owner_address="$(resolve_single_account_identity "${TOKEN_OWNER}")"

if ! is_ta_address "${creator_address}"; then
  die "Resolved creator is not a Thru address: ${creator_address}"
fi

if ! is_ta_address "${token_owner_address}"; then
  die "Resolved token owner is not a Thru address: ${token_owner_address}"
fi

if resume_enabled && [[ -n "${TOKEN_MINT_ADDRESS:-}" && -n "${TOKEN_ACCOUNT_ADDRESS:-}" ]]; then
  log "Resume enabled and token state already exists (${TOKEN_MINT_ADDRESS}). Set FORCE_RUN=1 to initialize a new token."
  exit 0
fi

prepare_network_activity "token initialization"

log "Initializing token mint ${ticker}."
run_cmd_retry "Initializing token mint" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" token initialize-mint \
  "${creator_address}" \
  "${ticker}" \
  "${mint_seed}" \
  --mint-authority "${mint_authority_address}" \
  --freeze-authority "${freeze_authority_address}" \
  --decimals "${TOKEN_DECIMALS}" \
  --fee-payer "${FEE_PAYER}"
mint_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Token mint initialization failed."
fi

run_cmd_capture "Deriving token mint address" "${THRU_BIN}" token derive-mint-account "${creator_address}" "${mint_seed}"
derive_mint_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Unable to derive the token mint address."
fi
mint_address="$(extract_last_account "${derive_mint_output}")"

[[ -n "${mint_address}" ]] || die "Unable to parse the token mint address."

log "Initializing token account for ${TOKEN_OWNER}."
run_cmd_retry "Initializing token account" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" token initialize-account \
  "${mint_address}" \
  "${token_owner_address}" \
  "${account_seed}" \
  --fee-payer "${FEE_PAYER}"
account_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Token account initialization failed."
fi

run_cmd_capture "Deriving token account address" "${THRU_BIN}" token derive-token-account \
  "${mint_address}" \
  "${token_owner_address}" \
  --seed "${account_seed}"
derive_account_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Unable to derive the token account address."
fi
token_account="$(extract_last_account "${derive_account_output}")"

[[ -n "${token_account}" ]] || die "Unable to parse the token account address."

mint_signature="$(extract_last_signature "${mint_output}")"
token_signature="$(extract_last_signature "${account_output}")"
TOKEN_TICKER="${ticker}"
TOKEN_MINT_SEED="${mint_seed}"
TOKEN_ACCOUNT_SEED="${account_seed}"
TOKEN_MINT_ADDRESS="${mint_address}"
TOKEN_ACCOUNT_ADDRESS="${token_account}"
LAST_TX_SIGNATURE="${token_signature:-${mint_signature}}"
export TOKEN_TICKER TOKEN_MINT_SEED TOKEN_ACCOUNT_SEED TOKEN_MINT_ADDRESS TOKEN_ACCOUNT_ADDRESS LAST_TX_SIGNATURE

write_env_file "${STATE_DIR}/token.env" \
  "LAST_RUN_TAG=${run_tag}" \
  "TOKEN_TICKER=${ticker}" \
  "TOKEN_MINT_SEED=${mint_seed}" \
  "TOKEN_ACCOUNT_SEED=${account_seed}" \
  "TOKEN_MINT_ADDRESS=${mint_address}" \
  "TOKEN_ACCOUNT_ADDRESS=${token_account}" \
  "TOKEN_MINT_AMOUNT=${TOKEN_MINT_AMOUNT}" \
  "TOKEN_MINT_SIGNATURE=${mint_signature}" \
  "TOKEN_ACCOUNT_SIGNATURE=${token_signature}"

log "Saved token details to ${STATE_DIR}/token.env."
