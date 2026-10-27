#!/bin/bash
T=/home/nickolay/xnuwork/xnu
F=$T/bsd/dev/sweet_ufs.c
echo "== block size / sector handling =="
grep -n 'sector\|block_size\|blocksize\|BLOCK\|512\|0x1000\|4096' "$F" | head -40
echo
echo "== A51-relevant constants already in the tree =="
grep -n 'UFS_ADT_NODE\|UFS_DEFAULT_PART\|0x13520000\|1352' "$F" | head -20
echo
echo "== wake-up / LUN 0xD0 =="
grep -n '0xd0\|0xD0\|START STOP\|start_stop\|power condition\|POWER' "$F" | head -20
