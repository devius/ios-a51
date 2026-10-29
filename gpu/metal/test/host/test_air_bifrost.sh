#!/bin/bash
# air_bifrost on our own fixture (fixtures/quad.metal, built with Xcode's metal).
#   gpu/metal/test/host/test_air_bifrost.sh [AIR_BIFROST]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="${1:-${GPU_METAL_WORK:-$HOME/.cache/a51-metal}/build/src/panfrost/compiler/air_bifrost}"
LIB="$HERE/fixtures/quad.metallib"
fail=0
check() {  # name, expected exit (0 or nonzero), pattern, function
  local name="$1" want="$2" pat="$3" fn="$4" out rc
  out="$("$BIN" --gpu-id 0x6221 "$LIB" "$fn" 2>&1)"; rc=$?
  if { [ "$want" = 0 ] && [ $rc -ne 0 ]; } || { [ "$want" != 0 ] && [ $rc -eq 0 ]; } || ! grep -qE "$pat" <<<"$out"; then
    echo "FAIL $name (exit $rc): $(tail -2 <<<"$out")"; fail=1
  else
    echo "PASS $name"
  fi
}
[ -x "$BIN" ] || { echo "FAIL: $BIN not built"; exit 1; }
check vertex_compiles        0 'function=quad_vertex stage=vertex bytes=[1-9]'       quad_vertex
check fragment_compiles      0 'function=quad_fragment stage=fragment bytes=[1-9]'   quad_fragment
check reports_function_constants 0 'function=quad_fragment_fc .*constants=1'          quad_fragment_fc
check unknown_function       1 'no function'                                          no_such_function
exit $fail
