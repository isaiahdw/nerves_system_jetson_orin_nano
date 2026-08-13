################################################################################
#
# nvidia-oot (NVIDIA out-of-tree kernel modules for Jetson, L4T r39.2)
#
################################################################################

# public_sources.tbz2 carries sub-tarballs; the OOT module sources are
# in Linux_for_Tegra/source/kernel_oot_modules_src.tbz2. See
# docs/m4-cuda.md for the full source map.
NVIDIA_OOT_VERSION = 39.2.0
NVIDIA_OOT_SITE = https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/sources
NVIDIA_OOT_SOURCE = public_sources.tbz2
NVIDIA_OOT_LICENSE = GPL-2.0-only, BSD-3-Clause, MIT
NVIDIA_OOT_DEPENDENCIES = linux

# The sub-tarball carries its own top-level Makefile plus nvidia-oot/,
# nvgpu/, hwpm/ and the nv-public device-tree material.
define NVIDIA_OOT_EXTRACT_CMDS
	cd $(@D) && \
		$(TAR) -x -j -f $(NVIDIA_OOT_DL_DIR)/$(NVIDIA_OOT_SOURCE) \
			Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 && \
		$(TAR) -x -j -f Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 && \
		rm -rf Linux_for_Tegra && \
		find $(@D) -name Makefile -not -path "*conftest*" -exec sed -i -E 's/-Werror[^ ]*//g' {} + && \
		sed -i 's|^obj-m += oak/|# obj-m += oak/ (Marvell NIC, does not build under gcc14; never used here)|' \
			$(@D)/nvidia-oot/drivers/net/ethernet/marvell/Makefile
endef

# Mirrors meta-tegra's nvidia-kernel-oot EXTRA_OEMAKE for tegra234,
# minus the display modules (headless system). The top-level Makefile in
# the module source drives nvidia-oot + nvgpu + hwpm.
NVIDIA_OOT_MAKE_ENV = \
	KERNEL_HEADERS=$(LINUX_DIR) \
	KERNEL_OUTPUT=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	IGNORE_PREEMPT_RT_PRESENCE=1 \
	NVIDIA_DISPLAY_MODULE_TARGETS= \
	NVIDIA_DISPLAY_MODULE_INSTALL_TARGETS= \
	kernel_name=oot

# NOTE: never suppress -Werror for conftest (neither via CC nor the
# Makefile strip): its type probes depend on "struct declared inside
# parameter list" warnings being fatal. With them suppressed every
# type reads as present and the build picks post-6.8 kernel APIs.
# The strip above therefore excludes conftest's Makefile.
# dtbs too: the upstream kernel DT has no GPU (ga10b) node on t234, so
# nvgpu never probes under it. The OOT tree builds NVIDIA's full "-nv"
# device trees (including tegra234-p3768-0000+p3767-0004-nv.dtb, the
# exact 4GB-module DT the stock image boots) - kernel, modules and DT
# all from the same L4T release.
define NVIDIA_OOT_BUILD_CMDS
	$(MAKE) -C $(@D) $(LINUX_MAKE_FLAGS) $(NVIDIA_OOT_MAKE_ENV) \
		CC="$(TARGET_CC) -std=gnu17" LD="$(TARGET_LD)" AR="$(TARGET_AR)" \
		OBJCOPY="$(TARGET_OBJCOPY)" \
		modules
	$(MAKE) -C $(@D) $(LINUX_MAKE_FLAGS) $(NVIDIA_OOT_MAKE_ENV) \
		CC="$(TARGET_CC) -std=gnu17" LD="$(TARGET_LD)" AR="$(TARGET_AR)" \
		OBJCOPY="$(TARGET_OBJCOPY)" \
		dtbs
endef

define NVIDIA_OOT_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) $(LINUX_MAKE_FLAGS) $(NVIDIA_OOT_MAKE_ENV) \
		modules_install
	find $(@D) -name "tegra234-p3768*-nv.dtb" -exec cp -v {} $(BINARIES_DIR)/ \;
endef

$(eval $(generic-package))
