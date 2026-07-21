#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

expected_config='!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/pettachainer/metta/logic_config)'
expected_compiler='!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/pettachainer/metta/compile)'
mapfile -t upstream_imports < <(grep -F '!(import! &self /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/' compiler/mm2_chainer.metta)

if [[ "${#upstream_imports[@]}" -ne 2 ||
      "${upstream_imports[0]}" != "$expected_config" ||
      "${upstream_imports[1]}" != "$expected_compiler" ]]; then
  printf 'production harness must import only PeTTaChainer compiler frontend dependencies:\n' >&2
  printf '%s\n' "${upstream_imports[@]}" >&2
  exit 1
fi

if grep -R -n -F '/PeTTaChainer/pettachainer/metta/' \
    compiler tests/harness/generated \
    --include='*.metta' | grep -v -F "$expected_config" | grep -v -F "$expected_compiler"; then
  echo 'runtime and generated tests must not import other PeTTaChainer modules' >&2
  exit 1
fi

if grep -R -n -F 'mm2_chainer_compat' compiler tests scripts README.md \
    --exclude='test_import_boundary.sh'; then
  echo 'obsolete compatibility-loader reference remains' >&2
  exit 1
fi

if grep -R -n -E 'mm2-compiler-view-(open|close|add|remove)' \
    compiler tests scripts README.md; then
  echo 'obsolete PeTTa compiler-view materialization remains' >&2
  exit 1
fi

tmp_dir="$(mktemp -d /tmp/mm2-boundary.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

MM2_HARNESS_VERDICT_LOG="$tmp_dir/verdicts" \
  timeout 30s petta tests/harness/production_boundary.metta \
  >"$tmp_dir/output" 2>&1

if grep -Eq 'mm2-test-(close|FAIL)' "$tmp_dir/verdicts"; then
  cat "$tmp_dir/output" >&2
  cat "$tmp_dir/verdicts" >&2
  exit 1
fi

pass_count="$(grep -c '^[(]mm2-test-pass ' "$tmp_dir/verdicts" || true)"
if [[ "$pass_count" != 10 ]]; then
  cat "$tmp_dir/output" >&2
  cat "$tmp_dir/verdicts" >&2
  echo "expected 10 production-boundary passes, got $pass_count" >&2
  exit 1
fi

echo "PASS: compiler-only production import and direct MORK metadata lookup"
