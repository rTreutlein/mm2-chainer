#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash scripts/build-runtime.sh outputs/harness_runtime.mm2

out="$(mktemp /tmp/mm2-member-inheritance-native-XXXXXX.log)"
trap 'rm -f "$out"' EXIT

petta tests/harness/member_inheritance_native.metta >"$out" 2>&1
cat "$out"

if grep -qE 'notsupported-ir|mm2-test-FAIL|ERROR' "$out"; then
  exit 1
fi

test "$(grep -c 'mm2-test-pass' "$out")" -eq 5
