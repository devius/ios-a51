#!/bin/bash
# Host tests for the A51 GPU's pure code (bsd/dev/a51_gpu_mmu.h).
set -euo pipefail
cd "$(dirname "$0")"
out=$(mktemp)
trap 'rm -f "$out"' EXIT
cc -std=c11 -Wall -Wextra -Werror -o "$out" test_mmu.c
"$out"
