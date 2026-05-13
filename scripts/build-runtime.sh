#!/usr/bin/env bash

set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "usage: $0 OUTPUT [SEED]" >&2
  exit 2
fi

output="$1"
seed="${2:-}"

mkdir -p "$(dirname "$output")"

{
  if [[ -n "$seed" ]]; then
    cat "$seed"
    printf '\n'
  fi

  cat runtime/parts/00_frontier.mm2
  printf '\n'
  cat runtime/parts/10_premises.mm2
  printf '\n'
  cat runtime/parts/20_proofs.mm2
  printf '\n'
  cat runtime/parts/30_merge.mm2
  printf '\n'
  cat runtime/parts/90_loop.mm2
} > "$output"
