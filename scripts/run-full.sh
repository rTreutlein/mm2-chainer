#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/full_runtime.mm2 runtime/default_seed.mm2

rules_file="${MM2_FULL_RULES:-outputs/full_rules.mm2}"
bash scripts/prepare-conceptnet-rules.sh "$rules_file"

mork run "$rules_file" --steps 1000 --aux-path outputs/full_runtime.mm2 outputs/full_run.mm2

echo '== merged Animal fact =='
sed -n '/^(fact (Animal x) /p' outputs/full_run.mm2

echo '== supporting merged facts =='
sed -n '/^(fact (Pet x) /p' outputs/full_run.mm2
sed -n '/^(fact (Mammal x) /p' outputs/full_run.mm2

echo '== Animal proofs =='
sed -n '/^(proved (Animal x) /p' outputs/full_run.mm2

echo '== proof records =='
sed -n '/^(proved /p' outputs/full_run.mm2 | sed -n '1,20p'
