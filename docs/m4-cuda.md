# M4: GPU / CUDA / TensorRT integration

Goal: the Orin Nano's 512-core Ampere iGPU (20 TOPS INT8) usable from
Elixir via Ortex + ONNX Runtime's TensorRT execution provider. All
inference is on-device (owner decision 2026-08-13; no cloud tier).

## Source map (mirrors meta-tegra master, L4T r39.2.0 / JetPack 7.2)

| Piece | Source | Reference recipe |
|---|---|---|
| OOT kernel modules (nvidia-oot, nvgpu, hwpm, display) | `https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/sources/public_sources.tbz2` (295 MB, sha256 `87d2e31ff55beaf2373e2f288538585995b231fd5745ec21f39a668e36efab2f`) → inner `Linux_for_Tegra/source/kernel_oot_modules_src.tbz2` + `nvidia_kernel_display_driver_source.tbz2` | `recipes-kernel/nvidia-kernel-oot/` |
| GPU firmware (GSP etc., `/lib/firmware/nvidia/...`) + proprietary Tegra libs | BSP driver tarball `Jetson_Linux_R39.2.0_aarch64.tbz2` (same release dir) | `recipes-bsp/tegra-binaries/` |
| CUDA / cuDNN / TensorRT userland | debs from `https://repo.download.nvidia.com/jetson` (JetPack 7.2 feed) | `recipes-devtools/cuda/`, `l4t_deb_pkgfeed.bbclass` |

Build facts from `nvidia-kernel-oot.inc`:
- Standard out-of-tree module build against the kernel:
  `KERNEL_HEADERS=<kernel src> KERNEL_OUTPUT=<kernel build>`, top-level
  Makefile comes from the BSP (`tegra-kernel-makefile`), target set for
  tegra234 adds `NVIDIA_DISPLAY_MODULE_TARGETS="nvidia-display"`.
- meta-tegra's patches mostly fix builds against *newer* kernels
  (6.18/linux-yocto, gcc-14); our kernel is the noble 6.8 tree the
  modules are developed against, so expect few or none needed.
- The modules deliberately replace some in-tree drivers: host1x,
  tegra-bpmp-thermal, tegra-drm — blacklist/ordering care needed.

## JetPack 7.2 userland version stack (from meta-tegra master, verified 2026-08-13)

| Component | Version | Recipe reference |
|---|---|---|
| CUDA | 13.2 (cudart 13.2.75-1) | `recipes-devtools/cuda/` |
| CUDA compat driver | 595.58.03-1ubuntu1 | `cuda-compat` |
| cuDNN | 9.20.0.46-1 | `recipes-devtools/cudnn/` |
| TensorRT | 10.16.2.10-1 | `recipes-devtools/gie/` |

Debs fetched from `https://repo.download.nvidia.com/jetson` +
class/pool paths per `l4t_deb_pkgfeed.bbclass`; version suffix pattern
`<name>_<ver>_arm64.deb`.

**Engine strategy (owner decision 2026-08-13):** build-on-first-run —
the full TensorRT builder ships in the production image; the
application builds engines from ONNX at first startup and caches them
on the data partition (survives A/B updates; TRT upgrades invalidate
the cache and trigger a natural rebuild). No lean-runtime diet image,
no golden-device engine pipeline. The 4 GiB slots / ~2.5 GB rootfs are
the production shape.

**Smoke-test strategy:** `tensorrt-trtexec-prebuilt` — trtexec ships as
a prebuilt binary, so GPU+CUDA+TensorRT can be proven end-to-end
(`trtexec --onnx=<model>`) with no CUDA cross-compilation. Ortex/ONNX
Runtime comes after that proof.

## GPU userspace packaging notes (next work item)

- BSP driver tarball: `https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/release/Jetson_Linux_R39.2.0_aarch64.tbz2`
  (1.2 GB, sha256 `1626626cd827de0e350b8802033b9da653c69b2290accedb9e5d01f49607e099`;
  pre-seeded in `~/.nerves/dl/tegra-libs/`).
- `package/tegra-libs` (plan): mirror `tegra-libraries-cuda` +
  `tegra-libraries-core` from meta-tegra master — libcuda.so.1.1 comes
  from `opt/nvidia/l4t-gpu-libs/<CUDA_DRV_VARIANT>/` (the 595-series
  compat driver dir), plus libnvidia-ptxjitcompiler, libnvidia-nvvm,
  and the RM stack (libnvrm_gpu/mem/host1x/chip, libnvos, ...) from
  `usr/lib/aarch64-linux-gnu/nvidia/` inside the deb-payload area of
  the tarball. Read those two recipes for the full lists and symlink
  farm.
- Then `package/cuda-cudart` (deb), `package/tensorrt-*` (debs incl.
  the prebuilt trtexec), `package/cudnn` (deb) — versions in the table
  above.
- Rootfs will blow past the 1 GiB slot immediately: do the 4 GiB GPT
  relayout with the first oversized build (full reflash via USB drive).

**Status 2026-08-13:** GPU inference verified on hardware. Kernel side
(nvgpu/hwpm modules, -nv DTBs, /dev/nvgpu/igpu0), userspace
(package/tegra-libs: CUDA driver stack + GA10B firmware;
package/tensorrt-runtime: TensorRT 10.16 + cuda-cudart + trtexec), and
the 4 GiB slot relayout are all deployed.
`trtexec --onnx=mnist.onnx` builds and runs an engine on the iGPU
(10.7k qps, 57 µs mean GPU compute). Remaining: Ortex/ONNX Runtime
TensorRT-EP proof from IEx.

## Plan

1. `package/nvidia-oot`: build nvidia-oot + nvgpu (+hwpm) modules from
   public_sources against the system kernel. Skip display (headless).
   First milestone: `/dev/nvgpu/igpu0` appears, `nvgpu` probes.
2. `package/tegra-firmware`: GSP/GPU firmware blobs from the BSP tarball.
3. `package/tegra-libs` + `package/cuda-runtime`: minimal .so set for
   ONNX Runtime + TensorRT EP (NOT the full toolkit — image budget).
   Start from meta-tegra's split and prune hard; target < 2.5 GB rootfs.
4. GPT relayout: rootfs slots 1 GiB → 4 GiB (breaking change, full
   reflash via USB-boot procedure in provisioning.md). fwup delta
   updates become important at this size.
5. Proof workload: Ortex with a Jetson-built `libonnxruntime` (NVIDIA
   publishes Jetson ONNX Runtime builds; TensorRT EP) running a small
   detection model from IEx.

## Constraints

- 4 GB RAM shared with the GPU — every megabyte in the image and at
  runtime matters; models must be small/quantized.
- CUDA userland is glibc-linked: our toolchain is glibc, compatible.
- NVIDIA userspace expects Ubuntu-ish paths and `ldconfig` — expect
  path/rpath fixups (meta-tegra shows the known set).
- The apt feed's JetPack 7.2 packages must match L4T r39.2 (same
  generation as the kernel and, eventually, the QSPI firmware).
