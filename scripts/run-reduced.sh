#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/reduced_runtime.mm2 runtime/default_seed.mm2

mork run rules/reduced_rules.mm2 --steps 220 --aux-path outputs/reduced_runtime.mm2 outputs/reduced_run.mm2

echo '== merged animal fact =='
sed -n '/^(fact (Animal /p' outputs/reduced_run.mm2

echo '== proofs for animal =='
sed -n '/^(proved (Animal /p' outputs/reduced_run.mm2

echo '== merged proof ids =='
sed -n '/^(proof-merged /p' outputs/reduced_run.mm2

echo '== all facts =='
sed -n '/^(fact /p' outputs/reduced_run.mm2
