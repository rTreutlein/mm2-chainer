#!/usr/bin/env bash

set -euo pipefail

mapfile -t shell_scripts < <(find scripts tests -maxdepth 2 -type f -name '*.sh' | sort)
bash -n "${shell_scripts[@]}"

bash scripts/check-generated-corpus.sh
bash tests/test_dumppln_converter.sh
bash tests/test_examples.sh
bash tests/test_runtime.sh
bash scripts/run-harness-corpus.sh
