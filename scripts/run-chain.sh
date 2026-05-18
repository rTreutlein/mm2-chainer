#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/chain_runtime.mm2

mork run demos/chain.mm2 --steps 260 --aux-path outputs/chain_runtime.mm2 outputs/chain_run.mm2

echo '== merged Creature fact =='
sed -n '/^(fact (Creature /p' outputs/chain_run.mm2

echo '== intermediate facts =='
sed -n '/^(fact (Mammal /p' outputs/chain_run.mm2
sed -n '/^(fact (Animal /p' outputs/chain_run.mm2

echo '== all facts =='
sed -n '/^(fact /p' outputs/chain_run.mm2
