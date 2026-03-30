# X Article Package

## Title
From Setup to Chain

## Cover Image
Use:
`./assets/x-article-cover.svg`

X recommends a `5:2` image ratio. This cover is prepared for that format.

## Insert Order
1. Cover image: `./assets/x-article-cover.svg`
2. After the "Toolkit Flow" section: `./assets/thru-flow.svg`
3. After the "Verified On-Chain Results" section: `./assets/thru-results.svg`
4. After the "What This Run Taught Me" section: `./assets/thru-lessons.svg`

## Body
Real deploy, real state, real fixes.

I wanted a run I could repeat, not a screenshot I could post once.

So I took Thru Alphanet from a fresh local setup to verified on-chain state, fixed the places where the docs and the live tooling disagreed, and turned the result into a small toolkit I can actually reuse.

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

I was not trying to save a pretty terminal log. I wanted a setup I could come back to next week and still trust.

That pushed the repo in a practical direction:

- one local account
- clean setup
- health checks before network actions
- retries for flaky steps
- saved logs and state after each run
- proxy checks for connectivity, but not disguised account activity

That became the toolkit.

## Where the Work Got Real

The docs helped. The useful part started when the commands hit a real machine and a real chain.

### The CLI surface had drifted

Some older examples still point to commands that do not exist on the installed CLI version. The quickest example was `keys show`.

It simply was not there.

The available flow was built around `list`, `get`, `generate`, `add`, and `rm`, so the scripts had to be written against the CLI on the machine, not the one older examples seemed to assume.

### Alias and address were not interchangeable

For a few token and nameservice steps, a local alias like `default` was not enough. The CLI wanted a real `ta...` address.

Once that was clear, the fix was straightforward: resolve the alias once, save the public key, and feed the right value into the commands that actually need it.

### A failed setup step was not actually a failed setup

On a repeated run, `account create` returned a nonce error.

That could have stopped the whole setup, but the account already existed on-chain and was usable. The right move was to verify state and continue, not blindly trust the first red line in the terminal.

### Success output still needed verification

The nameservice flow exposed the same thing from the other side. A record was created with the wrong templated value because of a bug in my own defaults. The command completed. The state was wrong. I fixed the template and corrected the record on-chain.

That was the clearest reminder in the whole run: command success is not the same thing as correct state.

## Verified On-Chain Results

These are the addresses from the run.

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

The addresses are useful. The more important part is that the path to get them is now boring in a good way.

The repo now keeps:

- per-step logs
- current state snapshots
- run history
- retry behavior
- RPC health checks
- resume support for repeated runs

That is what makes the whole thing reusable.

## What This Run Taught Me

What I got out of this run was not the screenshot. It was the cleanup work behind it.

You only really learn a stack by running the flow, finding the weak spots, and fixing the boring parts nobody screenshots.

That is what this repo is now: a practical single-account Thru Alphanet toolkit with real chain state behind it.

If you're building on Thru, the repo is here:

[https://github.com/Zhekinmaksim/thru-activity-toolkit](https://github.com/Zhekinmaksim/thru-activity-toolkit)
