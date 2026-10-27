#!/bin/bash
# Name the kernel functions containing the given addresses (unslid kernel).
# Usage: sym.sh KERNEL ADDR...
k=$1; shift
llvm-nm -n --defined-only "$k" | awk 'NF >= 3' > /tmp/sym.$$
for a in "$@"; do
	v=$(printf '%d' "$a" 2>/dev/null || python3 -c "print(int('$a',16))")
	awk -v A="${a#0x}" '{ if (tolower($1) <= tolower(A)) last=$0; else { print last; exit } }' /tmp/sym.$$ |
		sed "s/^/$a  /"
done
rm -f /tmp/sym.$$
