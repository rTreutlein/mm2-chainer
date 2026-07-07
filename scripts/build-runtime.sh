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

  for part in runtime/parts/*.mm2; do
    cat "$part"
    printf '\n'
  done
} > "$output"
