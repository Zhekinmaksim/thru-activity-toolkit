#!/usr/bin/env python3
import argparse
import struct
import sys


def padded_seed_hex(seed: str) -> bytes:
    raw = seed.encode("ascii")
    if len(raw) > 32:
        raise ValueError("ASCII counter seed must be 32 bytes or less")
    return raw.ljust(32, b"\x00")


def create_payload(account_index: int, seed: str, proof_hex: str) -> str:
    proof = bytes.fromhex(proof_hex)
    payload = bytearray()
    payload += struct.pack("<I", 0)
    payload += struct.pack("<H", account_index)
    payload += padded_seed_hex(seed)
    payload += struct.pack("<I", len(proof))
    payload += proof
    return payload.hex()


def increment_payload(account_index: int) -> str:
    return (struct.pack("<I", 1) + struct.pack("<H", account_index)).hex()


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create")
    create.add_argument("account_index", type=int)
    create.add_argument("seed")
    create.add_argument("proof_hex")

    increment = subparsers.add_parser("increment")
    increment.add_argument("account_index", type=int)

    args = parser.parse_args()

    try:
        if args.command == "create":
            print(create_payload(args.account_index, args.seed, args.proof_hex))
        else:
            print(increment_payload(args.account_index))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
