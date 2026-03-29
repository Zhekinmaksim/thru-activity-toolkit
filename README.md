# Thru Activity Automation

This workspace provides a small, official-docs-aligned automation scaffold for Thru Alphanet:

- `setup`: configure the CLI, install the Thru toolchain and C SDK, create a local key alias, create an on-chain account, and request faucet funds
- `health-check`: verify RPC connectivity before you spend time on a full run
- `test-proxies`: run RPC health checks through each proxy listed in `config/proxies.txt`
- `build`: compile the sample C counter program
- `deploy`: deploy the sample counter program
- `counter-create`: derive a counter address, request a state proof, and create counter state
- `counter-inc`: increment the last created counter
- `token-init`: create a token mint and token account
- `nameservice-init`: create a registrar or subdomain flow and append a record

The implementation follows the official Thru guides:

- Setup the DevKit: https://docs.thru.org/program-development/setting-up-thru-devkit
- Building a C Program: https://docs.thru.org/program-development/building-a-c-program
- Token Program Commands: https://docs.thru.org/cli-reference/token-commands
- Name Service Commands: https://docs.thru.org/cli-reference/name-service-commands

## Safety Boundaries

This scaffold intentionally does not support:

- raw private key ingestion from flat files
- proxy rotation
- multi-account batching meant to disguise or vary behavior

The official docs recommend using the CLI's local key management instead of sharing or storing raw private keys in plain text. The scripts here follow that guidance and use local key aliases such as `default`.

## Why Activities Differ Slightly

Each network activity generates a small run-specific suffix for seeds, labels, and names. That keeps repeated testnet runs from colliding with already-created program, token, counter, and domain accounts. The variation is for idempotence and easier testing, not for disguise.

## Quick Start

1. Copy the config templates:

```bash
cp config/app.env.example config/app.env
cp config/keys.env.example config/keys.env
cp config/account.txt.example config/account.txt
cp config/proxy.txt.example config/proxy.txt
cp config/proxies.txt.example config/proxies.txt
```

2. Either put your local `thru-cli` key alias into `config/account.txt`, or let `just setup` ask for it on first run.

3. Optionally put one proxy URL into `config/proxy.txt`.

4. If you want to test several proxies, put one proxy URL per line into `config/proxies.txt`.

5. Adjust the values in `config/app.env` and, if needed, `config/keys.env`.

6. Run the flow:

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

## Notes

- The network scripts request faucet funds before each on-chain activity.
- The network scripts run an RPC health check before each on-chain activity.
- Network commands use retries. Tune them with `NETWORK_RETRY_ATTEMPTS`, `NETWORK_RETRY_SLEEP`, `RPC_HEALTHCHECK_ATTEMPTS`, and `RPC_HEALTHCHECK_SLEEP` in `config/app.env`.
- A random delay between 30 and 60 seconds is enabled by default for network activity. Set `ACTIVITY_DELAY_ENABLED=0` in `config/app.env` if you want faster local iteration.
- Successful steps write aggregate state to `state/current.env` and `state/current.txt`, plus `state/last-action.env` and `state/history.tsv`.
- `just test-proxies` writes per-proxy results to `state/proxy-results.tsv` and a short summary to `state/proxy-test.env`.
- Resume is enabled by default for deploy/create/init steps. Set `FORCE_RUN=1` in `config/app.env` when you intentionally want a fresh program, counter, token, or nameservice run.
- State from successful actions is written to `state/*.env` so the next script can reuse the latest program, counter, token, or nameservice addresses.
- `config/account.txt` should contain one local key alias such as `default`, not a raw private key.
- If `config/proxy.txt` contains a URL, the scripts export it as `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` for the current run.
- `config/proxies.txt` is only for proxy reachability testing. It does not create multiple accounts or batch account activity.
- For nameservice test values, use `__RUN_TAG__` in `NAMESERVICE_RECORD_VALUE_TEMPLATE` if you want a per-run suffix.
- `just setup` stores the chosen alias and parsed public address in `state/account.env`.
