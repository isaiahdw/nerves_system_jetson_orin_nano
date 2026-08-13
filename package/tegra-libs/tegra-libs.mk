################################################################################
#
# tegra-libs (NVIDIA proprietary GPU userspace from the L4T BSP tarball)
#
################################################################################

TEGRA_LIBS_VERSION = 39.2.0
TEGRA_LIBS_SITE = https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.0/release
TEGRA_LIBS_SOURCE = Jetson_Linux_R$(TEGRA_LIBS_VERSION)_aarch64.tbz2
TEGRA_LIBS_LICENSE = NVIDIA-L4T (proprietary, redistributable)
TEGRA_LIBS_DEPENDENCIES = host-zstd

TEGRA_LIBS_DEB_VER = 39.2.0-20260601141651
TEGRA_LIBS_DEBS = \
	nvidia-l4t-core_$(TEGRA_LIBS_DEB_VER)_arm64.deb \
	nvidia-l4t-cuda_$(TEGRA_LIBS_DEB_VER)_arm64.deb \
	nvidia-l4t-cuda-nvgpu_$(TEGRA_LIBS_DEB_VER)_arm64.deb

# Pull just the needed debs out of the 1.2 GB tarball, then unpack each
# (a .deb is an ar archive; GNU tar cannot read it directly).
define TEGRA_LIBS_EXTRACT_CMDS
	cd $(@D) && \
		$(TAR) -x -j -f $(TEGRA_LIBS_DL_DIR)/$(TEGRA_LIBS_SOURCE) \
			$(addprefix Linux_for_Tegra/nv_tegra/l4t_deb_packages/,$(TEGRA_LIBS_DEBS)) && \
		for d in $(TEGRA_LIBS_DEBS); do \
			mkdir -p unpack && cd unpack && \
			ar -x ../Linux_for_Tegra/nv_tegra/l4t_deb_packages/$$d && \
			$(HOST_DIR)/bin/zstd -dcf data.tar.zst | $(TAR) -x -C $(@D) && \
			cd $(@D) && rm -rf unpack; \
		done && \
		rm -rf Linux_for_Tegra
endef

# Install the library payloads flat into /usr/lib (the Nerves layout),
# including the nvgpu-variant libcuda. ldconfig links are created
# explicitly since no ldconfig runs on target.
define TEGRA_LIBS_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib
	if [ -d $(@D)/usr/lib/aarch64-linux-gnu ]; then \
		cp -a $(@D)/usr/lib/aarch64-linux-gnu/nvidia/. $(TARGET_DIR)/usr/lib/ 2>/dev/null || true; \
		find $(@D)/usr/lib/aarch64-linux-gnu -maxdepth 1 -type f -name "*.so*" \
			-exec cp -a {} $(TARGET_DIR)/usr/lib/ \; ; \
	fi
	if [ -d $(@D)/opt/nvidia/l4t-gpu-libs/nvgpu ]; then \
		cp -a $(@D)/opt/nvidia/l4t-gpu-libs/nvgpu/. $(TARGET_DIR)/usr/lib/; \
	fi
	cd $(TARGET_DIR)/usr/lib && \
		for lib in libcuda libnvidia-ptxjitcompiler libnvidia-nvvm; do \
			real=$$(ls $$lib.so.* 2>/dev/null | sort -V | tail -1); \
			[ -n "$$real" ] && ln -sf $$real $$lib.so && ln -sf $$real $$lib.so.1 || true; \
		done
endef

$(eval $(generic-package))
