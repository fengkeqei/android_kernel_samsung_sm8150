# BUILD.md — SM-G9730 (beyond1q) 美版官方内核 4.14.190 构建与打包记录

> 目标设备：SM-G9730（国行硬件，beyond1q，SM8150 / 骁龙855），当前运行原厂 Android 12（One UI 4.x，五件套 G9730ZCU8HZE1 基础）。
> 本仓库：三星官方开源 SM-G973U_NA_12_Opensource（美版 NA / Android 12），内核 **4.14.190**。

## 1. 为什么以这份源码为基线

此前所有自编译内核（4.14.357 基线，含 tomxi/sukisu 及其衍生）在**原厂系统**上只要开启任何 RKP 选项就在启动早期挂死（`input_event` 等 `BRK #4`，debug monitor 异常）。根因：

- RKP 启动时 `rkp_init()`（`init/main.c`）通过 `uh_call(UH_APP_RKP, RKP_START, _text, _etext, ...)`（`arch/arm64/kernel/uh_entry.S` 中的 SMC 调用）把**编译期常量** `_text/_etext` 传给 TrustZone；
- 设备 TZ 里的 RKP app 按它烧录时期待的 **4.14.190 布局**登记/保护页面；
- 4.14.357 树代码布局已漂移（167 个 stable 补丁 + 各树自带改动），TZ 保护了错误的页面 → 后续对这些页面的任何写入触发 BRK 异常。
- 官方美版 4.14.190 的布局与 TZ 期待一致，因此 RKP 全开也能正常启动（原厂固件本身如此，stock Image 内含 66,630 个 JOPP magic）。

**结论：以官方 4.14.190 为基线，RKP/KDP 相关全部可用；后续需要的上游/新特性以补丁形式向这份基线合并，而不是反过来。**

## 2. 编译链（toolchain）

| 组件 | 版本 | 路径 | 用途 |
|---|---|---|---|
| Clang | **10.0.6**（Snapdragon LLVM ARM Compiler，`llvm-arm-toolchain-ship-10.0`） | `$TOOLCHAIN_DIR/llvm-arm-toolchain-ship-10.0/llvm-arm-toolchain-ship/10.0/bin/clang` | `REAL_CC` / `CFP_CC`，`CLANG_TRIPLE=aarch64-linux-gnu-`。需把它的 `../lib` 加进 `LD_LIBRARY_PATH` |
| binutils | NDK **r16b** 自带 aarch64-linux-android-4.9（binutils 2.27） | `$TOOLCHAIN_DIR/ndk-r16b/android-ndk-r16b/toolchains/aarch64-linux-android-4.9/prebuilt/linux-x86_64/bin/` | `CROSS_COMPILE`（ld / objcopy 等不由 clang 驱动时使用） |
| make | **4.3** | `$TOOLCHAIN_DIR/tools/make-4.3/bin/make` | 系统自带 make 版本过老/行为差异，统一用这份 |
| Python | **2.7.18** | `python2`（本机 `/usr/sbin/python2.7`） | **硬性要求**。`PYTHON=python2`；`scripts/rkp_cfp/` 与 link 阶段 FIPS 脚本是 Python2 代码，系统 `python` 是 3.x 会直接 SyntaxError |
| DTC | 源码树自带 | `tools/dtc`（配 `CONFIG_BUILD_ARM64_DT_OVERLAY=y`） | dtbo 相关 |
| 模板镜像 | 原厂 OS12 boot.img | `/home/dev/Projects/stockboot-template/boot-stock-os12.img`（md5 `66bbbc967d361a541f88f33443637ee9`，67,108,864 字节） | 打包用，见 §5 |

`GIT_BIN=false CURL_BIN=false`：不依赖 git/curl 做版本戳。

`KBUILD_BUILD_USER=dpi KBUILD_BUILD_HOST=21DN2A11 KBUILD_BUILD_VERSION=2`：与原厂 banner 一致。

## 3. 构建步骤

```bash
./build_usa190.sh            # 配置 beyond1qlte_usa_single_defconfig 并编 Image
./build_usa190.sh --clean    # 干净重编（删整个 OUT 目录）
```

产物：`$TOOLCHAIN_DIR/out-usa190/arch/arm64/boot/Image`，**47,120,400 字节，与原厂 Image 尺寸一致**。
环境变量 `TOOLCHAIN_DIR` / `OUT_DIR` 可覆盖默认路径（见脚本头部注释）。

验证 Image 有效性：偏移 `0x38` 处 magic `ARMd`（u32 0x644d5241 小端），`text_offset` 字段 = 0x80000。

## 4. 注意事项（踩过的坑）

1. **`size_append` 性能坑（已修，commit `6a4f4e5`）**：原厂 `scripts/Makefile.lib` 的 `size_append` 用 `$(shell stat ...)` 对整个依赖列表求值，发生在**每个子 make 解析 Makefile 时**（686 个文件、约 44KB 命令行），单这一项就把构建拖到小时级。已改为 recipe 执行时惰性求值（`cat|wc -c`），输出格式不变。若换干净源码重编，必须带上这个补丁。
2. **Python2 是硬性要求**：`PYTHON=python2` 必须传给 make。开 CFP 后若构建脚本直接调 `python`（而非 `$PYTHON`），需要 PATH 前置一个 `python → python2.7` 的 shim 目录（本机做法：`/tmp/py2bin/python` 软链）。**本机有 python2，不要改脚本去适配 python3。**
3. **换行符**：三星开源包内大量文件是 CRLF。本仓库 `scripts/Makefile.lib` 已归一为 LF（含功能修改），其余文件保持原样，diff 时注意。
4. **一次只跑一个构建**：两份并发 make 会抢磁盘 IO，看起来像卡死。每个 `out-*` 目录约 21GB，旧产物要及时清。
5. **out-of-tree 构建**：`O=` 到源码树外，源码树保持干净，git diff 才有意义。
6. **`cred` 结构**：本树已是 `atomic_t usage`（与 TZ 侧定义一致）。若从其它树合并 cred 相关代码，保持 `atomic_t`，不要带过来 `atomic_long_t`。
7. **`skip_initramfs` 必须加**：见 §5，ABL 不会自动追加。
8. **CFP（JOPP/ROPP）暂时关闭**：当前 defconfig 只开了 UH_RKP / KDP / NS_PROT / DMAP_PROT，`RKP_CFP*` 全部 not set（分级验证中）。原厂是全开（含 `RKP_CFP_ROPP_SYSREGKEY`）。重新打开 CFP 时注意第 2 条 python2 问题（`scripts/rkp_cfp/instrument.py` 要往 vmlinux 插 JOPP magic）。

## 5. 打包方式（boot.img 模板法）

不用 mkbootimg 从零组包，而是**以原厂 boot.img 为模板原位替换内核**，这是已验证可开机的做法：

- 原厂 boot.img（v1 头，page 4096）：内核 blob 从第 2 页（offset 4096）开始，`kernel_size` 在头偏移 8；
- 内核 blob 结构：`UNCOMPRESSED_IMG` 头（20 字节，偏移 16 是负载长度）+ 原厂 Image + **DTB 尾巴（997,113 字节）**。本内核不产 `Image-dtb`，尾巴必须从模板里抠出来原样拼接；
- 新 blob = 同样 20 字节头（写入我们 Image 的长度）+ 我们的 Image + 原厂 DTB 尾巴；
- 头部只改两处：`kernel_size = len(new_blob)`；cmdline（偏移 64，512 字节域）在原 cmdline 后追加 ` skip_initramfs`；
- **`id` 字段保留原厂值不重算**；其余字段（分区 64MB 填充、ramdisk/second 偏移等）全部保持模板原样；
- `skip_initramfs` 的作用：ABL 不会替我们追加这个参数，内核若不跳过内嵌 initramfs，会把 ramdisk 当根文件系统，init 起来后 `Could not stat("/")`、挂 `/product` 失败然后重启循环。

```bash
python3 pack_boot_stock.py \
    /home/dev/Projects/stockboot-template/boot-stock-os12.img \
    $TOOLCHAIN_DIR/out-usa190/arch/arm64/boot/Image \
    boot-out.img            # 默认追加 skip_initramfs，可再加自定义参数
```

脚本已用当前构建验证：产出与手工打包**逐字节一致**（md5 `054ba2a795db78dc1a6312715bcc2468`）。

## 6. 刷入与验证

```bash
adb push boot-out.img /sdcard/          # md5 两侧核对
# 手机进 OrangeFox：Install → 选镜像 → Flash to: Boot
# 或原厂 root 下：dd if=/sdcard/boot-out.img of=/dev/block/by-name/boot
```

开机后核对：

```bash
adb shell cat /proc/version     # 应显示 4.14.190 (dpi@21DN2A11) ... #2 ...
adb shell getprop ro.build.fingerprint   # 系统侧不受影响，仍是原厂
```

失败回退：OrangeFox / Download 刷回任意已验证镜像或五件套 boot。

## 7. RKP 分级验证记录（2026-10-23）

| # | RKP 配置 | boot.img md5 | 结果 |
|---|---|---|---|
| 1 | 全关（UH_RKP/KDP/NS_PROT/DMAP_PROT 均 off） | `714940d60d9e7dd58634496701b668e4` | ✅ 开机，双卡正常 |
| 2 | UH_RKP + RKP_KDP | `a0ae5639e47e49e800615423b08ffab7` | ✅ 开机 |
| 3 | + RKP_NS_PROT + RKP_DMAP_PROT（当前 defconfig） | `054ba2a795db78dc1a6312715bcc2468` | 🔄 已推送 /sdcard 待验证 |
| 4 | + RKP_CFP_JOPP/ROPP（回到原厂全开） | — | ⏳ 待 #3 通过后 |

对照：4.14.357 基线任意 RKP 组合均在原厂 TZ 下 `BRK #4` 崩溃（详见 `WORKLOG-round71-rkp-root-cause.md`）。

## 8. 后续工作

- CFP 全开验证（回到与原厂一致的 defconfig）；
- 向 190 基线**按需**回移 A16 所需特性：`CONFIG_BPF_JIT`（190 默认关，A16 `netbpfload` 需要）、BPF prog_type 兼容层（sukisu 树 `e2da59279` 的 18→CGROUP_SKB 重映射思路）等，逐项验证 RKP 下不崩；
- KSU 集成（暂缓，先把 RKP 基线钉死）。

## 9. 传 GitHub

```bash
# GitHub 建空仓库 fengkeqei/android_kernel_samsung_sm8150-usa-a12 后：
git remote add origin git@github.com:fengkeqei/android_kernel_samsung_sm8150-usa-a12.git
git push -u origin usa-a12
```
