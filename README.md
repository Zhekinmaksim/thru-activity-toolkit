# Thru Activity Toolkit

This repository contains a small toolkit for Thru Alphanet. It follows the official Thru documentation and helps you run a practical single-account workflow for setup, build, deploy, counter interactions, token initialization, name service setup, and proxy reachability checks.

## Included Commands

- `setup`: configure the CLI, install the Thru toolchain and C SDK, create or reuse a local key alias, create an on-chain account, and request faucet funds
- `health-check`: verify RPC connectivity before running a longer flow
- `test-proxies`: run RPC health checks through each proxy listed in `config/proxies.txt`
- `build`: compile the sample C counter program
- `deploy`: deploy the sample counter program
- `counter-create`: derive a counter account, request a state proof, and create counter state
- `counter-inc`: increment the last created counter
- `token-init`: create a token mint and token account
- `nameservice-init`: create a root registrar or subdomain flow and append a record

## Official References

- [Setup the DevKit](https://docs.thru.org/program-development/setting-up-thru-devkit)
- [Building a C Program](https://docs.thru.org/program-development/building-a-c-program)
- [Token Program Commands](https://docs.thru.org/cli-reference/token-commands)
- [Name Service Commands](https://docs.thru.org/cli-reference/name-service-commands)

## Safety Boundaries

This project intentionally does not support:

- raw private key ingestion from flat files
- proxy rotation for account activity
- multi-account batching meant to disguise or vary behavior

The intended model is one locally managed `thru-cli` key alias, such as `default`, plus optional proxy testing for connectivity only.

## Why Run Data Changes Between Executions

Each on-chain activity uses a small run-specific suffix for seeds, labels, or names. This prevents repeated testnet runs from colliding with existing program, token, counter, or domain accounts. The variation is for idempotence and easier testing, not for disguise.

## Project Layout

- `config/`: example configuration files
- `scripts/`: executable automation scripts
- `counter-program/`: sample C counter program used by the workflow
- `state/`: generated runtime state files
- `logs/`: generated run logs

## Quick Start

1. Copy the configuration templates:

```bash
cp config/app.env.example config/app.env
cp config/keys.env.example config/keys.env
cp config/account.txt.example config/account.txt
cp config/proxy.txt.example config/proxy.txt
cp config/proxies.txt.example config/proxies.txt
```

2. Put your local `thru-cli` alias in `config/account.txt`, or let `setup` ask for it on first run.

Example:

```txt
default
```

3. Optionally place one proxy URL in `config/proxy.txt`.

4. If you want to test multiple proxies, add one proxy URL per line to `config/proxies.txt`.

5. Review `config/app.env` and, if needed, `config/keys.env`.

## Running the Workflow

You can use either `just` or direct script execution.

### Option 1: Use `just`

```bash
just setup
just health-check
just test-proxies
just build
just deploy
just counter-create
just counter-inc
just token-init
just nameservice-init
```

### Option 2: Run Scripts Directly

```bash
./scripts/setup.sh
./scripts/health-check.sh
./scripts/test-proxies.sh
./scripts/build.sh
./scripts/deploy.sh
./scripts/counter-create.sh
./scripts/counter-inc.sh
./scripts/token-init.sh
./scripts/nameservice-init.sh
```

## Configuration Notes

- `config/account.txt` should contain one local key alias such as `default`, not a raw private key.
- `config/proxy.txt` is used for a single proxy during a normal run.
- `config/proxies.txt` is used only for proxy reachability testing.
- `config/keys.env` is optional and can override role-specific values.
- For nameservice test values, use `__RUN_TAG__` in `NAMESERVICE_RECORD_VALUE_TEMPLATE` if you want a per-run suffix.

## Runtime Behavior

- The network scripts request faucet funds before each on-chain activity.
- The network scripts run an RPC health check before each on-chain activity.
- Network commands use retries. You can tune them with `NETWORK_RETRY_ATTEMPTS`, `NETWORK_RETRY_SLEEP`, `RPC_HEALTHCHECK_ATTEMPTS`, and `RPC_HEALTHCHECK_SLEEP` in `config/app.env`.
- A random delay between 30 and 60 seconds is enabled by default for network activity. Set `ACTIVITY_DELAY_ENABLED=0` if you want faster local iteration.
- Resume behavior is enabled by default for deploy and initialization steps. Set `FORCE_RUN=1` in `config/app.env` when you intentionally want a fresh run.

## Generated State and Logs

Successful runs update these files:

- `state/account.env`
- `state/program.env`
- `state/counter.env`
- `state/token.env`
- `state/nameservice.env`
- `state/current.env`
- `state/current.txt`
- `state/last-action.env`
- `state/history.tsv`

Proxy testing also writes:

- `state/proxy-results.tsv`
- `state/proxy-test.env`

Per-run logs are stored in `logs/`.

## Notes About Keys and Recovery

- The local alias is managed by `thru-cli`.
- You can read the private key for backup with `thru-cli keys get <alias>`.
- You can restore a key on another machine with `thru-cli keys add <alias> <64_hex_private_key>`.
- Do not commit or publish private keys, local config files, or generated runtime state.
