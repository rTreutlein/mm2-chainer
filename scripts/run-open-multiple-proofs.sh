#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/open_multiple_proofs_runtime.mm2

mork run demos/open_multiple_proofs.mm2 --steps 130 --aux-path outputs/open_multiple_proofs_runtime.mm2 outputs/open_multiple_proofs_run.mm2

echo '== merged Animal fact =='
sed -n '/^(fact (Animal /p' outputs/open_multiple_proofs_run.mm2

echo '== proofs for Animal ann =='
sed -n '/^(proved (Animal ann) /p' outputs/open_multiple_proofs_run.mm2

echo '== merge bookkeeping =='
sed -n '/^(proof-merged /p' outputs/open_multiple_proofs_run.mm2
