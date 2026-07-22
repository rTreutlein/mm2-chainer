#!/usr/bin/env bash

set -euo pipefail

output="${1:-outputs/full_rules.mm2}"
source_dump="${MM2_CONCEPTNET_DUMP:-../cnet/dumppln.txt}"

if [ -f "$output" ]; then
  exit 0
fi

if [ ! -f "$source_dump" ]; then
  echo "ConceptNet dump not found: $source_dump" >&2
  echo "Set MM2_CONCEPTNET_DUMP or generate the dump with the sibling cnet project." >&2
  exit 2
fi

mkdir -p "$(dirname "$output")"
python3 scripts/convert_dumppln_to_mm2_rules.py "$source_dump" "$output"
