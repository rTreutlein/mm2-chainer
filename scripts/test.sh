#!/usr/bin/env bash

set -euo pipefail

bash scripts/check-generated-corpus.sh
bash tests/test_runtime.sh
bash scripts/run-harness-corpus.sh
