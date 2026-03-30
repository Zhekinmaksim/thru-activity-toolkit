# From Setup to Chain

![Thru Alphanet Cover](./assets/thru-cover.svg)

Real deploy, real state, real fixes.

A lot of chain demos stay clean because they stop where the friction begins.

You get a screenshot, a few commands, and a repo nobody wants to rerun a week later.

I wanted to take Thru Alphanet from a fresh local setup to verified on-chain state, fix the rough edges along the way, and leave the result in a shape I could actually use again.

The run covered:

- set up the CLI and SDK
- build a C program
- deploy it
- create counter state
- increment that state on-chain
- initialize a token mint and token account
- register a nameservice entry

Repository:
[https://github.com/Zhekinmaksim/thru-activity-toolkit](https://github.com/Zhekinmaksim/thru-activity-toolkit)

## Toolkit Flow

I was not trying to collect a pretty terminal transcript. I wanted a path I could rerun without re-learning the whole stack.

That shaped the repo more than the demo itself. The goal became:

- one local account
- clean setup
- health checks before network actions
- retries for flaky steps
- saved logs and state after each run
- proxy checks for connectivity, but not disguised account activity

That became the toolkit.

![Workflow Overview](./assets/thru-flow.svg)

## Where the Work Got Real

The official docs were a good starting point. The real work started when they met the CLI that was actually installed and the chain state that was actually there.

That is where small mismatches started to matter.

### The CLI surface had drifted

Some older examples still point to commands that do not exist on the installed CLI version. The quickest example was `keys show`.

It was not there.

The available flow was built around `list`, `get`, `generate`, `add`, and `rm`, so the scripts had to be written against the CLI on the machine, not the one older examples seemed to assume.

### Alias and address were not interchangeable

For a few token and nameservice steps, a local alias like `default` was not enough. The CLI wanted a real `ta...` address.

Once that was clear, the fix was straightforward: resolve the alias once, save the public key, and feed the right value into the commands that actually need it.

### A failed setup step was not actually a failed setup

On a repeated run, `account create` returned a nonce error.

That could have been treated as a dead stop, but the account already existed on-chain and was usable. The right move was to verify state and continue, not blindly trust the first red line in the terminal.

### Success output still needed verification

One record was created with the wrong templated value because of a bug in my own defaults. The command completed, but the state was wrong. I fixed the template and corrected the record on-chain.

That was the clearest reminder in the run: command success is not the same thing as correct state.

## Verified On-Chain Results

This part is real. No placeholders. No mock data.

![On-Chain Results](./assets/thru-results.svg)

### Program

- Seed: `mycounter_20260329`
- Program account: `tabF3aOHYG7CFyXjWYsLlLNEhBfvl8qPB0SHhuPBRja8yJ`
- Meta account: `tamgZDkWAXpQNgJbg00RslpD0IHZYmVZDZWKQ2CYRSa9nq`

### Counter

- Counter account: `ta2JpVS6l7BdwXs612BXDQ1ZqoJ8O99kJ6SEiXuA0EqhVo`
- Counter value after increment: `1`

### Token

- Ticker: `TST202`
- Mint: `taxzKuw5i6sQkH0gbx13C7c0SEfDJin4Mupsp7_Ttznt71`
- Token account: `taHgtGNt2NWkPnsm74lLJsJnCatlB9YYE2Yoy5a8sSlK1Y`

### Nameservice

- Root registrar: `lab20260329`
- Subdomain: `dev20260329`
- Domain account: `taih_vT8HFiMqN9HbKqygeErG1knk1ewDut-hOOF3JBWdJ`
- Record:
  `github => https://example.invalid/20260329063703-a4a7`

## Why This Result Matters

The deployed addresses are useful. The path that produced them matters just as much.

The repo now keeps:

- per-step logs
- current state snapshots
- run history
- retry behavior
- RPC health checks
- resume support for repeated runs

That is what turns a one-time testnet session into a workflow you can trust on the next run too.

![Lessons Learned](./assets/thru-lessons.svg)

## What This Run Taught Me

The screenshot is fine. The cleanup work behind it matters more.

Instead of saying the docs "seem fine," you run the flow, hit the edges, fix what broke, and leave behind something sharper than what you started with.

That is what this repo is meant to be: a practical single-account Thru Alphanet toolkit with real chain state behind it.

If you're building on Thru, the repo is here:

[https://github.com/Zhekinmaksim/thru-activity-toolkit](https://github.com/Zhekinmaksim/thru-activity-toolkit)
