#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/multipremise_runtime.mm2

mork run demos/multipremise.mm2 --steps 90 --aux-path outputs/multipremise_runtime.mm2 outputs/multipremise_run.mm2

echo '== merged FlyingMammal fact =='
sed -n '/^(fact (FlyingMammal /p' outputs/multipremise_run.mm2

echo '== proofs =='
sed -n '/^(proved (FlyingMammal /p' outputs/multipremise_run.mm2

echo '== all facts =='
sed -n '/^(fact /p' outputs/multipremise_run.mm2
