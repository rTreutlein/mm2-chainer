#!/usr/bin/env bash

set -euo pipefail

bash tests/test_runtime.sh
bash scripts/run-harness-corpus.sh
