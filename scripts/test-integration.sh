#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MORK_ROOT="/nexus/Dev/OpenCog/MORK"
PATHMAP_ROOT="/nexus/Dev/OpenCog/PathMap"
PETTA_ROOT="/nexus/Dev/OpenCog/PeTTa"
PETTA_FFI_ROOT="$PETTA_ROOT/mork_ffi"

CARGO_HOME="${CARGO_HOME:-/cache/cargo}"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/cache/target}"
PETTA_FFI_BUILD="${PETTA_FFI_BUILD:-/cache/petta-ffi}"
PETTA_FFI_MODE="${MM2_INTEGRATION_PETTA_FFI:-0}"
RUSTFLAGS="${RUSTFLAGS:--C target-cpu=native -A dangerous_implicit_autorefs -A unsafe_op_in_unsafe_fn}"
export CARGO_HOME CARGO_TARGET_DIR RUSTFLAGS

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "integration error: missing canonical dependency file: $1" >&2
    exit 1
  fi
}

require_dir() {
  if [[ ! -d "$1" ]]; then
    echo "integration error: missing canonical dependency mount: $1" >&2
    exit 1
  fi
}

require_dir "$MORK_ROOT"
require_dir "$PATHMAP_ROOT"
require_file "$MORK_ROOT/Cargo.toml"
require_file "$PATHMAP_ROOT/Cargo.toml"

mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR" "$PETTA_FFI_BUILD"

echo "== build MORK CLI from canonical mount =="
cargo build --release --manifest-path "$MORK_ROOT/Cargo.toml" -p mork
export PATH="$CARGO_TARGET_DIR/release:$PATH"
command -v mork >/dev/null

echo "== focused mm2-chainer MORK runtime =="
cd "$ROOT_DIR"
bash scripts/run-reduced.sh

if [[ "$PETTA_FFI_MODE" != "1" ]]; then
  echo "SKIP/PENDING: PeTTa mork_ffi needs standalone project registration and a canonical mount (proposal_c13330a0b57f4c3a)"
  echo "PASS: focused tracked-source MORK integration"
  exit 0
fi

require_dir "$PETTA_ROOT"
require_dir "$PETTA_FFI_ROOT"
require_file "$PETTA_ROOT/src/main.pl"
petta_ffi_files=(
  Cargo.toml
  mork.c
  morkspaces.pl
)

petta_ffi_git=(git -c safe.directory="$PETTA_FFI_ROOT" -C "$PETTA_FFI_ROOT")
petta_ffi_toplevel="$("${petta_ffi_git[@]}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "$petta_ffi_toplevel" != "$PETTA_FFI_ROOT" ]]; then
  echo "PENDING: PeTTa FFI validation requires its standalone repository mounted at $PETTA_FFI_ROOT" >&2
  echo "PENDING: standalone registration proposal_c13330a0b57f4c3a" >&2
  exit 2
fi
if [[ -n "$("${petta_ffi_git[@]}" status --porcelain --untracked-files=normal)" ]]; then
  echo "PENDING: PeTTa FFI repository must be clean: $PETTA_FFI_ROOT" >&2
  exit 2
fi
for relative_path in "${petta_ffi_files[@]}"; do
  require_file "$PETTA_FFI_ROOT/$relative_path"
  if ! "${petta_ffi_git[@]}" ls-files --error-unmatch "$relative_path" >/dev/null 2>&1; then
    echo "PENDING: PeTTa FFI repository must track: $PETTA_FFI_ROOT/$relative_path" >&2
    exit 2
  fi
done
petta_ffi_commit="$("${petta_ffi_git[@]}" rev-parse HEAD)"
echo "PeTTa mork_ffi commit: $petta_ffi_commit"

echo "== build PeTTa MORK FFI from canonical mounts =="
cargo build \
  --release \
  --manifest-path "$PETTA_FFI_ROOT/Cargo.toml"
read -r -a swipl_flags <<<"$(pkg-config --cflags --libs swipl)"
gcc -shared -fPIC \
  -o "$PETTA_FFI_BUILD/morklib.so" \
  "$PETTA_FFI_ROOT/mork.c" \
  "${swipl_flags[@]}"

echo "== PeTTa no-file MORK FFI smoke =="
LD_PRELOAD="$CARGO_TARGET_DIR/release/libmork_ffi.so" \
  swipl --stack_limit=8g -q \
    -p "library=$PETTA_FFI_BUILD" \
    -s "$PETTA_ROOT/src/main.pl" -- mork

echo "PASS: focused MORK + tracked PeTTa FFI integration"
