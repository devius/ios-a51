#!/bin/bash
# Source checks for the kernel side of sub-project 3 (UI on the GPU):
#   check-gl-patches.sh XNU_TREE
# 0145 SweetSurface refuses IOSurface wrap selectors 6/7; 0146 a policy named
# "AMFI" answers dyld's query (call 90) for backboardd's first 2 launches unless
# a51gl=0, ENOPOLICY otherwise; 0147 SweetFramebuffer counts presents per second
# behind boot-arg a51fps.
set -uo pipefail
x=${1:?usage: $0 XNU_TREE}
ok=0
fail() { echo "FAIL: $*"; ok=1; }
em=$(sed -n '/IOSurfaceRootUserClient::externalMethod/,/^}/p' "$x/iokit/Kernel/arm/SweetSurface.cpp")
grep -q 'case 6:' <<<"$em" && grep -q 'case 7:' <<<"$em" && grep -A12 'case 6:' <<<"$em" | grep -q 'kIOReturnUnsupported' ||
	fail "SweetSurface externalMethod does not refuse selectors 6/7"
a=$x/bsd/kern/sweet_amfi.c
grep -qE '\.mpc_name *= *"AMFI"' "$a" || fail 'no MAC policy named exactly "AMFI"'
sys=$(sed -n '/^a51_amfi_dyld_syscall(/,/^}/p' "$a")
[[ -n $sys ]] || fail "no a51_amfi_dyld_syscall()"
grep -q '90' <<<"$sys" && grep -q 'ENOPOLICY' <<<"$sys" || fail "dyld syscall does not handle 90 / return ENOPOLICY"
grep -q 'backboardd' "$a" && grep -q 'a51gl' "$a" && grep -qE 'launches? *(<|>=) *2|A51_GL_MAX_LAUNCHES' "$a" ||
	fail "dyld answer not limited to backboardd, a51gl, 2 launches"
grep -qE '\(1ull? *<< *0\)' "$a" && grep -qE '\(1ull? *<< *1\)' "$a" && grep -qE '\(1ull? *<< *5\)' "$a" ||
	fail "dyld flag bits 0,1,5 missing"
grep -q 'a51fps' "$x/iokit/Kernel/arm/SweetFramebuffer.cpp" && grep -q 'presents/s' "$x/iokit/Kernel/arm/SweetFramebuffer.cpp" ||
	fail "SweetFramebuffer has no a51fps presents/s counter"
# 0148: exec adds DYLD_INSERT_LIBRARIES for backboardd (launchd dropped it).
grep -q 'a51_gl_env' "$x/bsd/kern/kern_exec.c" || fail "kern_exec.c does not call a51_gl_env"
grep -q '/private/var/a51gpu/gl-on' "$a" && grep -q 'DYLD_INSERT_LIBRARIES=" A51_GL_SHIM' "$a" ||
	fail "a51_gl_env lacks the gl-on switch or the DYLD_INSERT_LIBRARIES string"
[[ $ok == 0 ]] && echo "gl patch checks passed"
exit $ok
