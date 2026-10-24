# android_kernel_samsung_sm8150 (beyond1q / SM-G9730, SM8150)

Samsung SM-G9730 (beyond1q, Snapdragon 855 / SM8150) kernel based on the
official Samsung US opensource drop for Android 12 (**4.14.190**,
`beyond1qlte_usa_single_defconfig`), merged forward through every
kernel.org 4.14 stable release up to the 4.14.336 EOL point, then on to
**4.14.357** from the [OpenELA](https://github.com/openela/kernel-lts)
extended-LTS branch (`linux-4.14.y`).

## Branches

| Branch | Contents |
|---|---|
| `main` | 4.14.357-openela baseline, stock RKP configuration (clang 10 build) |
| `android16` | Android 16 bring-up branch: BPF userspace compatibility, **clang 21 build**, RKP-disabled defconfig variant |

## android16 branch highlights

- **A16 BPF userspace compatibility**: `BPF_PROG_QUERY`, prog_type
  18-30 remapped to CGROUP_SKB at load (netd/netbpfload satisfied,
  programs run through the interpreter), modern attach_type enum, named
  `query` union member (a plain port of the UAPI collides with the
  anonymous-union scope in clang).
- **Clang 21 build** (see below): the whole tree compiles and boots
  on device with the Android clang-r563880c toolchain.
- **RKP disabled** (`CONFIG_UH_RKP` and all `CONFIG_RKP_*` unset): the
  TrustZone RKP app stays resident and silently skips a kernel that
  never registers — verified on stock firmware. This removes the
  CFP instrumentation dependency (python2 + clang 10 pair) entirely.
  `drivers/uh` and `scripts/rkp_cfp` remain in-tree for anyone who
  wants to re-enable it with the legacy clang 10 toolchain.
- Kernel command line caveat: Samsung's ABL appends `skip_initramfs`
  on SAR devices. If you ship an initramfs (retrofit dynamic
  partitions), remove the `do_skip_initramfs` handling in
  `init/initramfs.c` or the bootloader-supplied initrd is discarded
  before unpack.

## Build (clang 21, android16)

| Component | Version | Notes |
|---|---|---|
| Clang | **21.0.0** (Android clang-r563880c, +pgo+lto+bolt) | via `REAL_CC`/`CFP_CC` (the tree builds through `scripts/gcc-wrapper.py`) |
| binutils | NDK r16b (`aarch64-linux-android-4.9`, binutils 2.27) | `CROSS_COMPILE`; used for hand-written `.S` files only |
| make | 4.3 | |
| Python | 2.7 | only `scripts/gcc-wrapper.py` |

```bash
C21=/path/to/prebuilts/clang/host/linux-x86/clang-r563880c/bin
NDK=/path/to/ndk-r16b/android-ndk-r16b/toolchains/aarch64-linux-android-4.9/prebuilt/linux-x86_64/bin
export PATH=$C21:$NDK:$PATH
make O=out ARCH=arm64 CROSS_COMPILE=$NDK/aarch64-linux-android- \
     REAL_CC=$C21/clang CFP_CC=$C21/clang \
     CLANG_TRIPLE=aarch64-linux-gnu- PYTHON=python2 \
     KBUILD_BUILD_USER=you KBUILD_BUILD_HOST=host \
     KBUILD_BUILD_VERSION=3 \
     KBUILD_BUILD_TIMESTAMP="$(date -u)" \
     beyond1qlte_usa_single_defconfig
make O=out -j32 ARCH=arm64 CROSS_COMPILE=$NDK/aarch64-linux-android- \
     REAL_CC=$C21/clang CFP_CC=$C21/clang \
     CLANG_TRIPLE=aarch64-linux-gnu- PYTHON=python2 \
     KBUILD_BUILD_USER=you KBUILD_BUILD_HOST=host \
     KBUILD_BUILD_VERSION=3 \
     KBUILD_BUILD_TIMESTAMP="$(date -u)"
```

**Set `KBUILD_BUILD_TIMESTAMP`**: the generated `compile.h` (and thus the
`Linux version` banner) is only refreshed when the version string
changes — incremental rebuilds otherwise keep a stale timestamp and you
cannot tell booted kernels apart.

### Clang 21 porting notes (applied in-tree)

1. **Assembler routing** (the core of the port): C files must go through
   the clang integrated assembler — clang 21 emits instructions the
   bundled GNU as 2.27 cannot parse. Hand-written `.S` files must go to
   the external GNU as — clang 21's IAS rejects GNU macro named-argument
   calls (`clock_gettime_return, shift=1`). Implemented as
   `-integrated-as` in `CLANG_FLAGS` (C) and `-fno-integrated-as` in
   `KBUILD_AFLAGS` (with `CLANG_FLAGS` still appended so the external as
   gets `--target`/`--prefix`).
2. **Samsung Makefile wrapper**: `CC` is always
   `scripts/gcc-wrapper.py $(REAL_CC)`. Passing `REAL_CC`/`CFP_CC` on
   the command line overrides the clang 10 default; without them the
   stack-protector probe fails.
3. **Warning policy**: `-Wno-strict-prototypes -Wno-implicit-int
   -Wno-deprecated-non-prototype -Wno-unused-but-set-variable -Wno-error`
   in `KBUILD_CFLAGS` (this is a gnu89 codebase; module-level
   `-Werror` in bcmdhd relaxed too), and `scripts/gcc-wrapper.py` no
   longer aborts on unknown warnings during the port.
4. **`-fmerge-constants`** removed from `KBUILD_CFLAGS` (unsupported by
   clang 21); `-Werror=implicit-int/strict-prototypes` probes disabled.
5. One genuine code fix: a missing `int` return type in
   `ss_dsi_panel_debug.c`.

The `Linux version` banner carries the toolchain identity — after a
boot, `cat /proc/version` proves which build is actually running.

## Build (clang 10, RKP-enabled — legacy, `main`)

| Component | Version | Notes |
|---|---|---|
| Clang | **10.0.6** (Snapdragon LLVM, `llvm-arm-toolchain-ship-10.0`) | `REAL_CC`/`CFP_CC`; add its `lib/` to `LD_LIBRARY_PATH` |
| binutils | NDK **r16b** (`aarch64-linux-android-4.9`, binutils 2.27) | `CROSS_COMPILE` |
| make | **4.3** | newer make also works but this is what the tree expects |
| Python | **2.7** (hard requirement) | CFP instrumentation (`scripts/rkp_cfp/`) and the FIPS integrity script in `scripts/link-vmlinux.sh` are python2-only |

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
for SAR kernels **without** an initramfs, splice in
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
- **CFP instrumentation** (clang 10/RKP-enabled builds) runs under
  `scripts/rkp_cfp/instrument.py` during the vmlinux link (python2). A
  correct run yields ~66.7k JOPP magic words (`00be7bad`,
  little-endian) in the Image; the stock OS12 image has 66,630 and any
  large mismatch means the instrumentation silently failed.
- **FIPS** crypto-integrity HMAC is regenerated at link time; if you
  touch crypto code the link must run the whole
  `link-vmlinux.sh` flow, not a manual objcopy.
- **`mke2fs.conf` note** (build system, not kernel): the ext4 features
  for system images must include `flex_bg`; Samsung's ABL checks the
  group-0 descriptor layout of the system filesystem.

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
| android16 / clang 21 | 4.14.357-openela, RKP off | boots on stock firmware; `clang version 21.0.0` in `/proc/version` |

## License

GPL-2.0, same as the kernel.
