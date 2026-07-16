#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MORK_ROOT="/nexus/Dev/OpenCog/MORK"
PATHMAP_ROOT="/nexus/Dev/OpenCog/PathMap"
PETTA_ROOT="/nexus/Dev/OpenCog/PeTTa"

CARGO_HOME="${CARGO_HOME:-/cache/cargo}"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/cache/target}"
PETTA_FFI_BUILD="${PETTA_FFI_BUILD:-/cache/petta-ffi}"
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
require_dir "$PETTA_ROOT"
require_file "$MORK_ROOT/Cargo.toml"
require_file "$PATHMAP_ROOT/Cargo.toml"
require_file "$PETTA_ROOT/mork_ffi/Cargo.toml"
require_file "$PETTA_ROOT/mork_ffi/mork.c"
require_file "$PETTA_ROOT/mork_ffi/morkspaces.pl"
require_file "$PETTA_ROOT/src/main.pl"

mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR" "$PETTA_FFI_BUILD"

echo "== build MORK CLI from canonical mount =="
cargo build --locked --release --manifest-path "$MORK_ROOT/Cargo.toml" -p mork
export PATH="$CARGO_TARGET_DIR/release:$PATH"
command -v mork >/dev/null

echo "== focused mm2-chainer MORK runtime =="
cd "$ROOT_DIR"
bash scripts/run-reduced.sh

echo "== build PeTTa MORK FFI from canonical mounts =="
cargo build \
  --locked \
  --release \
  --manifest-path "$PETTA_ROOT/mork_ffi/Cargo.toml"
read -r -a swipl_flags <<<"$(pkg-config --cflags --libs swipl)"
gcc -shared -fPIC \
  -o "$PETTA_FFI_BUILD/morklib.so" \
  "$PETTA_ROOT/mork_ffi/mork.c" \
  "${swipl_flags[@]}"

echo "== PeTTa no-file MORK FFI smoke =="
LD_PRELOAD="$CARGO_TARGET_DIR/release/libmork_ffi.so" \
  swipl --stack_limit=8g -q \
    -p "library=$PETTA_FFI_BUILD" \
    -s "$PETTA_ROOT/src/main.pl" -- mork

echo "PASS: focused MORK + PeTTa integration"
