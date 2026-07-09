#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fqx "$needle" "$file"; then
    fail "expected line in $file: $needle"
  fi
}

mkdir -p outputs

input="outputs/test_dumppln_converter_input.txt"
out="outputs/test_dumppln_converter_rules.mm2"

cat > "$input" <<'EOF'
(: proof-a (Implication (Premises (Dog $x)) (Conclusions (Pet $x))) (CTV (STV 0.7 0.976282) (STV 0 1)))
(: proof-b (Implication (Premises (Own $x) (Pet $x)) (Conclusions (Happy $x))) (CTV (STV 0.2 0.345) (STV 0.4 0.567)))
EOF

python3 scripts/convert_dumppln_to_mm2_rules.py "$input" "$out" >/dev/null

assert_contains "$out" '(ruleN (Pet $x) proof-a (ctv (0.7 0.976282) (0 1)) (pcons (Dog $x) pnil))'
assert_contains "$out" '(ruleN (Happy $x) proof-b (ctv (0.2 0.345) (0.4 0.567)) (pcons (Own $x) (pcons (Pet $x) pnil)))'

if grep -Fq '(ctv (1.0 1.0)' "$out"; then
  fail "converter flattened input CTVs to all-ones"
fi

echo "PASS: dumppln converter"
