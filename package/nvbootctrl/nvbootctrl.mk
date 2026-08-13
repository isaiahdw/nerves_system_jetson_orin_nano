################################################################################
#
# nvbootctrl (from NVIDIA's nvidia-l4t-tools Debian package)
#
################################################################################

# Track the r36.4 (JetPack 6 / UEFI 36.4.x) line to match the QSPI
# firmware generation. The deb carries many tools; only nvbootctrl is
# installed - it links nothing but libc (checked with readelf).
NVBOOTCTRL_VERSION = 36.4.4-20250616085344
NVBOOTCTRL_SITE = https://repo.download.nvidia.com/jetson/t234/pool/main/n/nvidia-l4t-tools
NVBOOTCTRL_SOURCE = nvidia-l4t-tools_$(NVBOOTCTRL_VERSION)_arm64.deb
NVBOOTCTRL_LICENSE = NVIDIA-L4T (proprietary, redistributable)
NVBOOTCTRL_DEPENDENCIES = host-zstd

# A .deb is an ar archive; GNU tar cannot read it directly.
define NVBOOTCTRL_EXTRACT_CMDS
	cd $(@D) && \
		ar -x $(NVBOOTCTRL_DL_DIR)/$(NVBOOTCTRL_SOURCE) && \
		$(HOST_DIR)/bin/zstd -dcf $(@D)/data.tar.zst | \
			$(TAR) -x -C $(@D) ./usr/sbin/nvbootctrl
endef

define NVBOOTCTRL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/nvbootctrl \
		$(TARGET_DIR)/usr/sbin/nvbootctrl
endef

$(eval $(generic-package))
