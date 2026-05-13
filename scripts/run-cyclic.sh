#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/cyclic_runtime.mm2

mork run demos/cyclic.mm2 --steps 80 --aux-path outputs/cyclic_runtime.mm2 outputs/cyclic_run.mm2

echo '== final facts =='
sed -n '/^(fact /p' outputs/cyclic_run.mm2

echo '== merged proof ids =='
sed -n '/^(proof-merged /p' outputs/cyclic_run.mm2

echo '== goal-paths (should NOT contain cyclic self-reference) =='
sed -n '/^(goal-path /p' outputs/cyclic_run.mm2
