#!/usr/bin/env bash

set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "usage: $0 OUTPUT [SEED]" >&2
  exit 2
fi

output="$1"
seed="${2:-}"
scheduler_batch_size="${MM2_SCHEDULER_BATCH_SIZE:-32}"

case "$scheduler_batch_size" in
  ''|*[!0-9]*)
    echo "MM2_SCHEDULER_BATCH_SIZE must be a positive integer, got: $scheduler_batch_size" >&2
    exit 2
    ;;
esac
if (( scheduler_batch_size < 1 )); then
  echo "MM2_SCHEDULER_BATCH_SIZE must be a positive integer, got: $scheduler_batch_size" >&2
  exit 2
fi

mkdir -p "$(dirname "$output")"

{
  if [[ -n "$seed" ]]; then
    cat "$seed"
    printf '\n'
  fi

  for part in runtime/parts/*.mm2; do
    if [[ "$part" == "runtime/parts/08_schedule.mm2" ]]; then
      sed "s/(head 32 /(head $scheduler_batch_size /g" "$part"
    else
      cat "$part"
    fi
    printf '\n'
  done
} > "$output"
