#!/usr/bin/env bash

set -euo pipefail

mkdir -p outputs
bash scripts/build-runtime.sh outputs/independent_runtime.mm2

mork run demos/independent.mm2 --steps 60 --aux-path outputs/independent_runtime.mm2 outputs/independent_run.mm2

echo '== merged Mammal fact =='
sed -n '/^(fact (Mammal /p' outputs/independent_run.mm2

echo '== merged Pet fact =='
sed -n '/^(fact (Pet /p' outputs/independent_run.mm2

echo '== all facts =='
sed -n '/^(fact /p' outputs/independent_run.mm2
