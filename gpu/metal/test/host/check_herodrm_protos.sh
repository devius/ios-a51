#!/bin/bash
# Every C declaration of herodrm's exports under gpu/ must have the return type
# of its definition in gpu/mesa/herodrm.c (review of stages 1-2: air_metal.c and
# a51_device_test.c declared herodrm_fault_count int, herodrm.c returns
# unsigned long long). Exit 1 names each mismatch.
set -u
G="$(cd "$(dirname "$0")/../../.." && pwd)"
bad=0
for fn in herodrm_fault_count herodrm_surface_import herodrm_bo_sync herodrm_prime_size; do
  def=$(grep -B1 -E "^$fn\(" "$G/mesa/herodrm.c" | head -1 | sed -E 's/^EXPORT //; s/[[:space:]]+$//')
  while IFS= read -r line; do
    file=${line%%:*}; decl=${line#*:}
    ret=$(sed -E "s/^[[:space:]]*(extern )?//; s/[[:space:]]*\*?$fn\(.*//" <<<"$decl")
    if [ "$ret" != "$def" ]; then echo "MISMATCH $fn: '$ret' in ${file#$G/} vs '$def' in mesa/herodrm.c"; bad=1; fi
  done < <(grep -rn -E "^[[:space:]]*(extern )?(int|unsigned|long|int64_t|uint64_t|uint32_t|void)[a-z_ 0-9]*[ *]$fn\([^)]*\);" "$G" --include='*.c' --include='*.m' --include='*.h' --include='*.inc' | grep -v "mesa/herodrm.c" | sed -E 's/:[0-9]+:/:/')
done
[ $bad = 0 ] && echo "herodrm prototypes match"
exit $bad
