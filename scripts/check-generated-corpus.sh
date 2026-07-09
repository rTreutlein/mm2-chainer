#!/usr/bin/env bash
# Verify generated PeTTaChainer corpus fixtures are in sync with the converter.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
. scripts/harness-common.sh

src_dir="../PeTTaChainer/pettachainer/metta/tests"
skip_files=()

python3 scripts/convert_petta_tests.py >/dev/null

mapfile -t unexpected < <(find tests/harness/generated -maxdepth 1 -type f -name '*.metta' ! -name 'test_*.metta' -print)
if [ "${#unexpected[@]}" -ne 0 ]; then
  printf 'unexpected generated corpus file: %s\n' "${unexpected[@]}" >&2
  exit 1
fi

if ! git diff --quiet -- tests/harness/generated; then
  git diff -- tests/harness/generated >&2
  echo "generated corpus is stale; run python3 scripts/convert_petta_tests.py" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

find "$src_dir" -maxdepth 1 -type f -name 'test_*.metta' -printf '%f\n' | sort > "$tmp_dir/upstream"
printf '%s\n' "${skip_files[@]}" | sort > "$tmp_dir/skipped"
comm -23 "$tmp_dir/upstream" "$tmp_dir/skipped" > "$tmp_dir/expected"
find tests/harness/generated -maxdepth 1 -type f -name 'test_*.metta' -printf '%f\n' | sort > "$tmp_dir/generated"
sed 's/\.metta$//' "$tmp_dir/generated" | sort > "$tmp_dir/generated-stems"
harness_floor_names | sort > "$tmp_dir/floor-stems"
sort -u "$tmp_dir/floor-stems" > "$tmp_dir/floor-stems-unique"

if ! diff -u "$tmp_dir/expected" "$tmp_dir/generated" >/dev/null; then
  diff -u "$tmp_dir/expected" "$tmp_dir/generated" >&2 || true
  echo "generated corpus file inventory does not match upstream tests minus explicit skips" >&2
  exit 1
fi

floor_err=0
while IFS= read -r duplicate_floor; do
  echo "duplicate corpus pass floor entry: $duplicate_floor" >&2
  floor_err=1
done < <(uniq -d "$tmp_dir/floor-stems")
while IFS= read -r missing_floor; do
  echo "missing corpus pass floor for generated fixture: $missing_floor" >&2
  floor_err=1
done < <(comm -23 "$tmp_dir/generated-stems" "$tmp_dir/floor-stems-unique")
while IFS= read -r stale_floor; do
  echo "stale corpus pass floor without generated fixture: $stale_floor" >&2
  floor_err=1
done < <(comm -13 "$tmp_dir/generated-stems" "$tmp_dir/floor-stems-unique")
if [ "$floor_err" -ne 0 ]; then
  exit 1
fi
