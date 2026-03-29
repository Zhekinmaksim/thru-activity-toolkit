# From Docs to Chain: Shipping a Real Thru Alphanet Workflow

![Thru Alphanet Cover](./assets/thru-cover.svg)

I spent this run doing something I usually trust other people to do for me: taking a fresh chain workflow from docs to a real on-chain result, fixing the rough edges along the way, and turning the whole thing into something I could rerun without dreading it.

This time the target was Thru Alphanet.

The goal was simple on paper:

- set up the CLI and SDK
- build a C program
- deploy it
- create and increment counter state
- initialize a token mint and token account
- register a nameservice entry

In practice, it turned into the kind of session that tells you whether a stack is actually usable or whether it only looks good in a quickstart.

Repository:
[https://github.com/Zhekinmaksim/thru-activity-toolkit](https://github.com/Zhekinmaksim/thru-activity-toolkit)

## What I Wanted to End Up With

I did not want another one-off terminal transcript.

I wanted a small toolkit that could:

- set up a single local account cleanly
- survive flaky RPC moments
- retry network steps
- keep logs and state between runs
- let me build and deploy without repeating the same manual steps
- test proxies separately without turning the repo into a multi-account spam tool

That became the shape of the repo.

![Workflow Overview](./assets/thru-flow.svg)

## What Actually Shipped

By the end of the session, the toolkit handled:

- `setup`
- `health-check`
- `test-proxies`
- `build`
- `deploy`
- `counter-create`
- `counter-inc`
- `token-init`
- `nameservice-init`

The C counter program compiled, deployed, and ran on-chain. The token flow worked. The nameservice flow worked. The repo was pushed cleanly to GitHub.

The most useful part, though, was not the happy path. It was the friction I hit and had to remove.

## The Rough Edges Were the Interesting Part

The current `thru-cli` behavior did not match every example I had seen.

That showed up immediately in a few places:

### 1. `keys show` was not available

Some examples still assume a `keys show` command. On the installed CLI version, the available key commands were `list`, `get`, `add`, `generate`, and `rm`.

That meant I had to stop treating old examples as canonical and start coding against the CLI that was actually on the machine.

### 2. Token commands wanted real Thru addresses

For token initialization, passing `default` as an alias was not enough for some arguments. The CLI expected real `ta...` addresses.

That is a small difference, but it is exactly the kind of thing that breaks an otherwise decent automation pass.

The fix was simple: resolve the local alias to the saved public key before calling token and nameservice steps that expect account pubkeys.

### 3. Account creation hit `NONCE_TOO_LOW`

This one was a good reminder that "failed" does not always mean "not usable."

`account create` returned a runtime nonce error on a repeated run, but the account already existed on-chain and was funded. So the correct behavior was not to keep pretending setup had failed. The correct behavior was to verify the account state and continue.

### 4. One nameservice record was created with a bad template value

I found a bug in my own templating logic, where the default placeholder for the nameservice record value was malformed. The flow still completed, but the record value was wrong.

That is exactly why I like doing full end-to-end verification instead of stopping at "command returned success."

I fixed the code and then corrected the record on-chain.

## The On-Chain Result

The nice part: the chain state is real, not hypothetical.

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

## Why the Toolkit Matters More Than the Demo

The deployed addresses are useful, but the more important outcome is the path that produced them.

What I have now is something I can rerun.

The repo keeps:

- per-step logs
- current state snapshots
- run history
- retry behavior
- health checks before network actions
- clean separation between single-run proxy checks and actual account activity

That may not sound glamorous, but it is the difference between a chain experiment and a developer tool you can keep using next week.

## What I Like About Thru So Far

The interesting part of this run was that once the inputs were correct, the chain did what it was supposed to do.

The counter flow behaved cleanly.
The token flow behaved cleanly.
The nameservice flow behaved cleanly.

The friction was mostly around real-world developer experience:

- exact CLI surface area
- argument expectations
- recovery from partially completed state
- verifying what happened after a command returns

That is not a criticism as much as it is the normal work of early infrastructure. The difference is whether someone takes the time to absorb those paper cuts and turn them into a better path.

That is what I wanted this repo to do.

## If You Want to Use It

The repo is here:

[https://github.com/Zhekinmaksim/thru-activity-toolkit](https://github.com/Zhekinmaksim/thru-activity-toolkit)

It is built around a single-account workflow and real chain verification, not fake screenshots and not theory.

If you are building on Thru Alphanet and want a practical starting point for:

- environment setup
- C program deployment
- state creation and execution
- token initialization
- nameservice setup
- proxy reachability checks

then this should save you a solid chunk of setup time.

And if you run into the same rough edges I did, at least now they are written down in code.

![Lessons Learned](./assets/thru-lessons.svg)
