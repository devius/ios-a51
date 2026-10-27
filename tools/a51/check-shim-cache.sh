#!/bin/bash
R=/mnt/g/a51-port/ios-a51/shim/a51
echo "== SCTLR / cache control in the shim =="
grep -rn 'SCTLR\|sctlr\|dcache\|dc \|ic \|MMU\|mmu_enable\|msr' "$R"/*.c "$R"/*.S "$R"/*.h | sed "s#$R/##" | head -50
echo
echo "== dcache_clean definition =="
grep -rn -A16 'dcache_clean' "$R"/*.h "$R"/*.c | sed "s#$R/##" | head -40
