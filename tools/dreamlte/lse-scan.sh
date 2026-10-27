#!/bin/bash
# List ARMv8.1 LSE instructions (illegal on Cortex-A53 / Exynos 8895) in a
# kernel Mach-O, counted per function. Usage: lse-scan.sh KERNEL
set -euo pipefail
llvm-objdump -d --no-show-raw-insn "$1" |
	grep -E '^[0-9a-f]+ <|	(cas|casa|casal|casl|casp|ldadd|ldclr|ldeor|ldset|ldsmax|ldsmin|ldumax|ldumin|stadd|stclr|steor|stset|stsmax|stsmin|stumax|stumin|swp)[a-z]*	' |
	awk '/^[0-9a-f]+ </{fn=$2; next} {n++; c[fn]++} END {printf "LSE instructions: %d\n", n+0; for (f in c) print c[f], f}' |
	sort -rn | head -40
