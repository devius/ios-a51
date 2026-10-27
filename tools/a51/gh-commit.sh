#!/bin/bash
# Keep the local git history in step with the working tree so the push is a
# single step once a write-capable token exists. Never prints the token.
set -uo pipefail
cd /mnt/g/a51-port/ios-a51 || exit 1
git config user.name nickdemon22
git config user.email nickdemon22@users.noreply.github.com
git config core.fileMode false
git add -A
echo "== staged =="
git diff --cached --name-status | sed 's/^/  /'
git commit -q -m "shim/a51: XNU payload handoff, UFS partition self-check, report refactor

payload_boot.c finds the SWEETXNU payload through /chosen/linux,initrd-* and
does the donor's proven copy + boot_args + jump sequence with A51 facts (4 KiB
pages, framebuffer 0xca000000 1080x2400 stride 4320). The same image stays a
diagnostic when the ramdisk has no payload. Report helpers moved behind
report.h so the loader can log through the same forged ramoops record.

ufs_probe.c now also reads back the boot partition (ANDROID! with the exact
flashed kernel_size) and the first userdata block, and lists the whole GPT.

mkboot.js gained --ramdisk/--ramdisk-compress and rewrites ramdisk_size.

Verified on hardware: boot 8, initrd 0x89000000-0x891a0800 found in S-Boot's
live FDT, payload_magic_ok=0 for the stock Android ramdisk." || echo "  (nothing to commit)"
echo
echo "HEAD: $(git rev-parse --short HEAD)  branch: $(git rev-parse --abbrev-ref HEAD)"
echo "files tracked: $(git ls-files | wc -l)"
echo "== sanity: no secrets or dumps tracked =="
git ls-files | grep -E '^backup/|^research/|\.img$|\.ipsw$|\.dtb$' || echo "  clean"
git grep -lE 'github[_]pat_[A-Za-z0-9_]{20,}|gh[p]_[A-Za-z0-9]{20,}|RZ8[A-Z0-9]{8}' -- . || echo "  no secrets in tracked files"
