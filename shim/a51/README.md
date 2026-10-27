# A51 shim (SM-A515F / Exynos 9611)

Boot-1 diagnostic payload for the Galaxy A51. It runs where S-Boot drops it
(EL1, MMU off), records the live hardware state into the Samsung log regions
that survive a warm reboot, paints the S-Boot framebuffer, and then asks the
bootloader for recovery.

## Build (Windows host)

```powershell
powershell -ExecutionPolicy Bypass -File shim\a51\build.ps1
```

Needs the xpack bare-metal GCC at
`G:\a51-port\toolchain\gcc\xpack-aarch64-none-elf-gcc-13.3.1-1.1\bin`.
Output: `shim\a51\out\loader.bin` (raw ARM64 `Image`, header at offset 0,
`text_offset = 0x80000`, `image_size` patched, zero absolute relocations —
the build refuses to link if any appear).

On Linux the same steps are `shim\a51\build.sh` with `CROSS=aarch64-none-elf-`.

## Pack a boot image

```powershell
node tools\a51\mkboot.js --list --stock backup\stock-boot.img
node tools\a51\mkboot.js --stock backup\stock-boot.img `
  --kernel shim\a51\out\loader.bin --out backup\boot-a51-test1.img
```

Only the kernel slot changes. Header, ramdisk, DTB, `recovery_dtbo`,
`SEANDROIDENFORCE` trailer and trailing bytes are copied byte-for-byte, and the
payload is gzipped when the stock kernel is gzipped. Until `stock-boot.img`
exists, `OrangeFox-Unofficial-a51.img` is an acceptable template: it is the same
header v2 / page 2048 / raw-kernel format.

`tools\a51\build-all.ps1` does both steps and prefers the stock image.

## Flash and collect

```powershell
powershell -ExecutionPolicy Bypass -File tools\a51\phase1-dump.ps1   # backups first
powershell -ExecutionPolicy Bypass -File tools\a51\flash-test1.ps1    # flash + readback + logs
powershell -ExecutionPolicy Bypass -File tools\a51\flash-test1.ps1 -Restore
```

`flash-test1.ps1` refuses to run without `backup\stock-boot.img`, because that
file is the only guaranteed way back.

## Log record

24 little-endian u64 slots at each of `0x91202000`, `0x91286000`, `0x91388000`,
`0xF9000000`; signature slot 0 is `"A51SHIM1"`.

| slot | content |
|------|---------|
| 1 | CurrentEL (4 = EL1) |
| 2 | SCTLR_EL1 (bit 0 must be 0: MMU off) |
| 3 | FDT pointer from S-Boot |
| 4 | image load PA (`adr _start`) |
| 5 | MPIDR_EL1 (0 on CPU0) |
| 6 | CNTFRQ_EL0 (should read back 26000000) |
| 7 | CNTPCT_EL0 sample |
| 8 | ID_AA64MMFR0_EL1 |
| 9 | GICD_TYPER @ 0x12301004 |
| 10 | UFS HCI version @ 0x13520008 |
| 11 | DECON GLOBAL_CONTROL |
| 12 | DECON SHADOW_REG_UPDATE_REQ |
| 13 | DECON HW_SW_TRIG_CONTROL |
| 14 | DECON HW_TE_CNT |
| 15 | DSIM STATUS |
| 16 | DPP0 IDMA `IN_BASE_ADDR_Y` — the address S-Boot's scanout reads |
| 17 | DPP0 IDMA `SRC_SIZE` |
| 18 | DPP0 IDMA `ENABLE` |
| 19 | framebuffer PA used for the paint |
| 20 | stage (1 entered main, 2 painted, 3 loop done, 4 PSCI fallback, 5 halted) |
| 21 | trigger-loop iterations |
| 22 | iterations/s x100 (proves the 26 MHz timebase) |
| 23 | run counter (caps the display loop at three boots) |

Slot 16 is the important one for Phase 4: whatever IDMA channel reports
`0xCA000000` is the channel XNU will page-flip through.

## Files

| file | role |
|------|------|
| `start.S` | ARM64 `Image` header, EL1 entry, stack, jump to `a51_main` |
| `main.c` | register capture, log records, framebuffer paint, DECON trigger loop, reset paths |
| `a51.ld` | linked at 0, `.text.head` first |
| `build.ps1` / `build.sh` | Windows / Linux build |
