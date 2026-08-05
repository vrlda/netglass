#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures/nettop
/usr/bin/nettop -n -L 1 -J bytes_in,bytes_out,interface,state,time \
  > Fixtures/nettop/capture-1.txt
head -1 Fixtures/nettop/capture-1.txt | grep -q '^time,,' \
  || { echo "nettop printed usage text, not a CSV header (flag/column problem?)" >&2; exit 1; }
echo "Captured $(wc -l < Fixtures/nettop/capture-1.txt) lines"
head -5 Fixtures/nettop/capture-1.txt
