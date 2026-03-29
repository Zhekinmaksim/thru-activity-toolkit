set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

setup:
    ./scripts/setup.sh

health-check:
    ./scripts/health-check.sh

test-proxies:
    ./scripts/test-proxies.sh

build:
    ./scripts/build.sh

deploy:
    ./scripts/deploy.sh

counter-create:
    ./scripts/counter-create.sh

counter-inc:
    ./scripts/counter-inc.sh

token-init:
    ./scripts/token-init.sh

nameservice-init:
    ./scripts/nameservice-init.sh
