# android_kernel_samsung_sm8150 (beyond1q / SM-G9730, SM8150)

Samsung SM-G9730 (beyond1q, Snapdragon 855 / SM8150) kernel based on the
official Samsung US opensource drop for Android 12 (**4.14.190**,
`beyond1qlte_usa_single_defconfig`), merged forward through every
kernel.org 4.14 stable release up to the 4.14.336 EOL point, then on to
**4.14.357** from the [OpenELA](https://github.com/openela/kernel-lts)
extended-LTS branch (`linux-4.14.y`).

Samsung's Real-time Kernel Protection (RKP / KDP / NS_PROT / DMAP_PROT /
CFP-JOPP / CFP-ROPP, i.e. the stock configuration) is **enabled and
verified working on device** at every step of the merge.

## Why the 4.14.190 baseline

Samsung's bootloader-level RKP app (TrustZone) expects the kernel code
layout it was burned with. `rkp_init()` hands TZ the kernel's
`_text/_etext` at boot; a kernel whose layout drifted too far from what
the TZ image was built for gets its pages protected wrongly and dies
early with BRK faults. The official 4.14.190 US drop matches the TZ on
this device, so RKP works; custom 4.14.3xx rebases did not. Merging
stable forward on top of 190 (instead of rebasing 190 onto 3xx) keeps
TZ happy — every intermediate level was booted and verified with a live
RKP session (`/proc/uh_log`).

## Build

### Toolchain

| Component | Version | Notes |
|---|---|---|
| Clang | **10.0.6** (Snapdragon LLVM, `llvm-arm-toolchain-ship-10.0`) | `REAL_CC`/`CFP_CC`; add its `lib/` to `LD_LIBRARY_PATH` |
| binutils | NDK **r16b** (`aarch64-linux-android-4.9`, binutils 2.27) | `CROSS_COMPILE` |
| make | **4.3** | newer make also works but this is what the tree expects |
| Python | **2.7** (hard requirement) | CFP instrumentation (`scripts/rkp_cfp/`) and the FIPS integrity script in `scripts/link-vmlinux.sh` are python2-only |

### Steps

```bash
# TOOLCHAIN_DIR must contain:
#   llvm-arm-toolchain-ship-10.0/llvm-arm-toolchain-ship/10.0/
#   ndk-r16b/android-ndk-r16b/toolchains/aarch64-linux-android-4.9/
#   tools/make-4.3/bin/make
export TOOLCHAIN_DIR=/path/to/toolchain
./build_usa190.sh              # builds out-of-tree, Image under the out dir
```

Product: `Image` (ARM64, uncompressed). A full build takes ~15 min on 8
threads.

### Packing a boot.img

The stock Android 12 `boot.img` for this device is a v1 header whose
kernel blob is `UNCOMPRESSED_IMG`-header + Image + DTB tail. To build a
flashable image: keep the stock header verbatim (including its `id`
field), patch `kernel_size`, append `skip_initramfs` to the cmdline
(the bootloader does not add it for you), splice in
`<new Image> + <stock DTB tail>` after the 20-byte
`UNCOMPRESSED_IMG` header, and zero-fill back to partition size
(64 MB). Without `skip_initramfs` the kernel treats the embedded
ramdisk as rootfs and init dies mounting `/product`.

## Gotchas learned during the merge

- **`scripts/Makefile.lib` `size_append`** evaluated `$(shell stat …)`
  for the whole dependency list at *parse* time of every sub-make
  (~686 files each). This made builds take hours. It is replaced with
  lazy recipe-time evaluation; output format unchanged.
- **Paired API changes must be reverted or kept together.** The
  stable series changed `cred.h`'s `put_cred`/`get_cred` (NULL check)
  and `net/core/sock.c` (drop the caller-side NULL check) as a pair;
  taking only one side produced a NULL deref in `__sk_destruct`. Same
  story for `wait.h`/`wait.c`/`signalfd.c` (POLLFREE trio) and
  `bits.h`/`const.h`/`memory.h` (`UL()` consolidation).
- **Half-applied series are the main hazard.** When a stable patch
  series reworks a file and only the later hunks conflict, the file can
  end up with new signatures but old call sites. The compiler catches
  most of it, but some (epoll loop restructure, extcon
  `device_register` reorder) compile fine and die at boot. When a
  boot-time crash points at a generically-reworked file, reverting that
  single file to the last known-booting state is the fastest fix.
- **extcon `device_register` reorder** (4.14.31x): stable moved
  `device_register(&edev->dev)` after the devm allocations. Samsung's
  tree never `device_initialize()`s that embedded device first, so the
  devres list head is still zeroed at devm time → NULL write. Kept at
  the Samsung order.
- **`msm_msi_config_access`** can be called with a NULL MSI domain
  during early PCIe RC suspend on this merge; guarded to warn+return.
- **Samsung-diverged areas kept as-is** (stable fixes skipped where the
  upstream fix presupposed mainline code shape): `drivers/android/binder*`
  (Samsung fork), Samsung ext4 xattr/inline exports, MPTCP-wrapped
  `tcp_output`/syncookies, `mm/slub.c` fastpath (`tid` update ordering),
  f2fs stack, `hci_sock` bind rework, `f_fs` acquire/release rework.
- **CFP instrumentation** runs under `scripts/rkp_cfp/instrument.py`
  during the vmlinux link (python2). A correct run yields ~66.7k JOPP
  magic words (`00be7bad`, little-endian) in the Image; the stock OS12
  image has 66,630 and any large mismatch means the instrumentation
  silently failed.
- **FIPS** crypto-integrity HMAC is regenerated at link time; if you
  touch crypto code the link must run the whole
  `link-vmlinux.sh` flow, not a manual objcopy.

## Merge history

| Level | Kernel | Result |
|---|---|---|
| baseline | 4.14.190 (Samsung US A12 drop) | boots, RKP live |
| +KDP | 4.14.190 | boots |
| +NS/DMAP | 4.14.190 | boots |
| +CFP (full stock RKP) | 4.14.190 | boots |
| stable batch 1 | 4.14.230 | boots |
| stable batch 2 | 4.14.270 | boots |
| stable batch 3 | 4.14.310 | boots |
| stable batch 4 (EOL) | 4.14.336 | boots |
| openela | **4.14.357** | boots; Wi-Fi, modem, dual SIM verified |

## License

GPL-2.0, same as the kernel.
