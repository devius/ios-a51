#!/bin/sh
# What does the WSL Ubuntu already have for building xnu and the shim?
echo "== identity =="
uname -m
. /etc/os-release; echo "$PRETTY_NAME"
echo
echo "== tools =="
for t in bash git clang clang-15 clang-16 clang-17 gcc make ninja python3 python \
         dtc cpio gzip lz4 xz bison flex patch curl wget rsync \
         aarch64-linux-gnu-gcc aarch64-none-elf-gcc lzfse xcrun; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '%-24s %s\n' "$t" "$(command -v "$t")"
  else
    printf '%-24s MISSING\n' "$t"
  fi
done
echo
echo "== clang/gcc versions =="
clang --version 2>/dev/null | head -2
gcc --version 2>/dev/null | head -1
echo
echo "== python modules =="
python3 -c 'import zlib,struct,hashlib; print("stdlib ok")' 2>&1
python3 -c 'import lzma; print("lzma ok")' 2>&1
echo
echo "== disk =="
df -h / /mnt/g 2>/dev/null | head -5
echo
echo "== home contents =="
ls -la ~ | head -20
echo
echo "== any prior xnu/sweet work? =="
ls -d ~/xnu* ~/*sweet* ~/*ios* /opt/* 2>/dev/null | head -20
