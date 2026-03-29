#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

bootstrap_env
detect_thru_bin
start_run_logging "nameservice-init"

run_tag="${RUN_TAG}"
seed_suffix="$(short_tag "${run_tag}")"
record_value="${NAMESERVICE_RECORD_VALUE_TEMPLATE//__RUN_TAG__/${run_tag}}"
record_value="${record_value//\{RUN_TAG\}/${run_tag}}"
nameservice_owner_address="$(resolve_single_account_identity "${NAMESERVICE_OWNER}")"
nameservice_authority_address="$(resolve_single_account_identity "${NAMESERVICE_AUTHORITY}")"

if ! is_ta_address "${nameservice_owner_address}"; then
  die "Resolved nameservice owner is not a Thru address: ${nameservice_owner_address}"
fi

if ! is_ta_address "${nameservice_authority_address}"; then
  die "Resolved nameservice authority is not a Thru address: ${nameservice_authority_address}"
fi

if resume_enabled && [[ -n "${NAMESERVICE_DOMAIN_ACCOUNT:-}" ]]; then
  log "Resume enabled and nameservice state already exists (${NAMESERVICE_DOMAIN_ACCOUNT}). Set FORCE_RUN=1 to create a new one."
  exit 0
fi

prepare_network_activity "nameservice initialization"

case "${NAMESERVICE_MODE}" in
  root)
    root_name="$(printf '%s' "${NAMESERVICE_ROOT_BASE}${seed_suffix}" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-16)"
    subdomain_name="$(printf '%s' "${NAMESERVICE_SUBDOMAIN_BASE}${seed_suffix}" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-16)"

    log "Initializing root registrar ${root_name}."
    run_cmd_retry "Initializing root registrar" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
      "${THRU_BIN}" nameservice init-root \
      "${root_name}" \
      --authority "${nameservice_authority_address}" \
      --fee-payer "${FEE_PAYER}"
    root_output="${RUN_OUTPUT}"
    if (( RUN_STATUS != 0 )); then
      die "Root registrar initialization failed."
    fi

    run_cmd_capture "Deriving registrar account" "${THRU_BIN}" nameservice derive-registrar-account "${root_name}"
    derive_registrar_output="${RUN_OUTPUT}"
    if (( RUN_STATUS != 0 )); then
      die "Unable to derive the registrar account."
    fi
    registrar_account="$(extract_last_account "${derive_registrar_output}")"
    [[ -n "${registrar_account}" ]] || die "Unable to parse the registrar account."

    log "Registering subdomain ${subdomain_name}."
    run_cmd_retry "Registering subdomain" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
      "${THRU_BIN}" nameservice register-subdomain \
      "${subdomain_name}" \
      "${registrar_account}" \
      --owner "${nameservice_owner_address}" \
      --authority "${nameservice_authority_address}" \
      --fee-payer "${FEE_PAYER}"
    subdomain_output="${RUN_OUTPUT}"
    if (( RUN_STATUS != 0 )); then
      die "Subdomain registration failed."
    fi

    run_cmd_capture "Deriving domain account" "${THRU_BIN}" nameservice derive-domain-account \
      "${registrar_account}" \
      "${subdomain_name}"
    derive_domain_output="${RUN_OUTPUT}"
    if (( RUN_STATUS != 0 )); then
      die "Unable to derive the domain account."
    fi
    domain_account="$(extract_last_account "${derive_domain_output}")"
    [[ -n "${domain_account}" ]] || die "Unable to parse the domain account."
    root_signature="$(extract_last_signature "${root_output}")"
    subdomain_signature="$(extract_last_signature "${subdomain_output}")"
    ;;
  subdomain)
    [[ -n "${NAMESERVICE_PARENT_ACCOUNT:-}" ]] || die "Set NAMESERVICE_PARENT_ACCOUNT when NAMESERVICE_MODE=subdomain."
    subdomain_name="$(printf '%s' "${NAMESERVICE_SUBDOMAIN_BASE}${seed_suffix}" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-16)"

    log "Registering subdomain ${subdomain_name} under ${NAMESERVICE_PARENT_ACCOUNT}."
    run_cmd_retry "Registering subdomain" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
      "${THRU_BIN}" nameservice register-subdomain \
      "${subdomain_name}" \
      "${NAMESERVICE_PARENT_ACCOUNT}" \
      --owner "${nameservice_owner_address}" \
      --authority "${nameservice_authority_address}" \
      --fee-payer "${FEE_PAYER}"
    subdomain_output="${RUN_OUTPUT}"
    if (( RUN_STATUS != 0 )); then
      die "Subdomain registration failed."
    fi

    run_cmd_capture "Deriving domain account" "${THRU_BIN}" nameservice derive-domain-account \
      "${NAMESERVICE_PARENT_ACCOUNT}" \
      "${subdomain_name}"
    derive_domain_output="${RUN_OUTPUT}"
    if (( RUN_STATUS != 0 )); then
      die "Unable to derive the domain account."
    fi
    registrar_account="${NAMESERVICE_PARENT_ACCOUNT}"
    domain_account="$(extract_last_account "${derive_domain_output}")"
    [[ -n "${domain_account}" ]] || die "Unable to parse the domain account."
    root_name=""
    root_signature=""
    subdomain_signature="$(extract_last_signature "${subdomain_output}")"
    ;;
  *)
    die "Unsupported NAMESERVICE_MODE=${NAMESERVICE_MODE}. Use root or subdomain."
    ;;
esac

log "Appending record ${NAMESERVICE_RECORD_KEY} to ${domain_account}."
run_cmd_retry "Appending nameservice record" "${NETWORK_RETRY_ATTEMPTS}" "${NETWORK_RETRY_SLEEP}" \
  "${THRU_BIN}" nameservice append-record \
  "${domain_account}" \
  "${NAMESERVICE_RECORD_KEY}" \
  "${record_value}" \
  --owner "${nameservice_owner_address}" \
  --fee-payer "${FEE_PAYER}"
record_output="${RUN_OUTPUT}"
if (( RUN_STATUS != 0 )); then
  die "Appending the nameservice record failed."
fi

record_signature="$(extract_last_signature "${record_output}")"
NAMESERVICE_ROOT_NAME="${root_name}"
NAMESERVICE_REGISTRAR_ACCOUNT="${registrar_account}"
NAMESERVICE_SUBDOMAIN="${subdomain_name}"
NAMESERVICE_DOMAIN_ACCOUNT="${domain_account}"
LAST_TX_SIGNATURE="${record_signature:-${subdomain_signature:-${root_signature}}}"
export NAMESERVICE_ROOT_NAME NAMESERVICE_REGISTRAR_ACCOUNT NAMESERVICE_SUBDOMAIN NAMESERVICE_DOMAIN_ACCOUNT LAST_TX_SIGNATURE

write_env_file "${STATE_DIR}/nameservice.env" \
  "LAST_RUN_TAG=${run_tag}" \
  "NAMESERVICE_ROOT_NAME=${root_name}" \
  "NAMESERVICE_REGISTRAR_ACCOUNT=${registrar_account}" \
  "NAMESERVICE_SUBDOMAIN=${subdomain_name}" \
  "NAMESERVICE_DOMAIN_ACCOUNT=${domain_account}" \
  "NAMESERVICE_RECORD_KEY=${NAMESERVICE_RECORD_KEY}" \
  "NAMESERVICE_RECORD_VALUE=${record_value}" \
  "NAMESERVICE_ROOT_SIGNATURE=${root_signature}" \
  "NAMESERVICE_SUBDOMAIN_SIGNATURE=${subdomain_signature}" \
  "NAMESERVICE_RECORD_SIGNATURE=${record_signature}"

log "Saved nameservice details to ${STATE_DIR}/nameservice.env."
