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

define NVIDIA_OOT_EXTRACT_CMDS
	cd $(@D) && \
		$(TAR) -x -j -f $(NVIDIA_OOT_DL_DIR)/$(NVIDIA_OOT_SOURCE) \
			Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 && \
		$(TAR) -x -j -f Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 && \
		rm -rf Linux_for_Tegra
endef

# Mirrors meta-tegra's nvidia-kernel-oot EXTRA_OEMAKE for tegra234,
# minus the display modules (headless system). The top-level Makefile in
# the module source drives nvidia-oot + nvgpu + hwpm.
NVIDIA_OOT_MAKE_ENV = \
	KERNEL_HEADERS=$(LINUX_DIR) \
	KERNEL_OUTPUT=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	IGNORE_PREEMPT_RT_PRESENCE=1 \
	kernel_name=oot

define NVIDIA_OOT_BUILD_CMDS
	$(MAKE) -C $(@D) $(LINUX_MAKE_FLAGS) $(NVIDIA_OOT_MAKE_ENV) \
		CC="$(TARGET_CC) -std=gnu17" LD="$(TARGET_LD)" AR="$(TARGET_AR)" \
		OBJCOPY="$(TARGET_OBJCOPY)" \
		modules
endef

define NVIDIA_OOT_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) $(LINUX_MAKE_FLAGS) $(NVIDIA_OOT_MAKE_ENV) \
		modules_install
endef

$(eval $(generic-package))
