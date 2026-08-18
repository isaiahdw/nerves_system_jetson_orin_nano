################################################################################
#
# tensorrt-runtime (TensorRT 10.16 + cudart 13.2 from the JetPack apt feed)
#
################################################################################

TENSORRT_RUNTIME_VERSION = 10.16.2.10
TENSORRT_RUNTIME_CUDART = cuda-cudart-13-2_13.2.75-1_arm64.deb
TENSORRT_RUNTIME_SITE = https://repo.download.nvidia.com/jetson/common/pool/main/t/tensorrt
TENSORRT_RUNTIME_SOURCE = libnvinfer10_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb
TENSORRT_RUNTIME_EXTRA_DOWNLOADS = \
	libnvinfer-lean10_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb \
	libnvinfer-plugin10_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb \
	libnvinfer-vc-plugin10_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb \
	libnvinfer-dispatch10_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb \
	libnvonnxparsers10_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb \
	libnvinfer-bin_$(TENSORRT_RUNTIME_VERSION)-1+cuda13.2_arm64.deb \
	https://repo.download.nvidia.com/jetson/common/pool/main/c/cuda-cudart/$(TENSORRT_RUNTIME_CUDART)
TENSORRT_RUNTIME_LICENSE = NVIDIA-TensorRT and CUDA EULAs (proprietary, redistributable)
TENSORRT_RUNTIME_DEPENDENCIES = host-zstd tegra-libs

define TENSORRT_RUNTIME_EXTRACT_CMDS
	cd $(@D) && \
		for d in $(TENSORRT_RUNTIME_SOURCE) $(notdir $(TENSORRT_RUNTIME_EXTRA_DOWNLOADS)); do \
			mkdir -p unpack && cd unpack && \
			ar -x $(TENSORRT_RUNTIME_DL_DIR)/$$d && \
			($(HOST_DIR)/bin/zstd -dcf data.tar.zst 2>/dev/null || cat data.tar.xz | xz -dc) | $(TAR) -x -C $(@D) && \
			cd $(@D) && rm -rf unpack; \
		done
endef

define TENSORRT_RUNTIME_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib $(TARGET_DIR)/usr/bin
	if [ -d $(@D)/usr/lib/aarch64-linux-gnu ]; then \
		find $(@D)/usr/lib/aarch64-linux-gnu -maxdepth 1 \( -type f -o -type l \) -name "*.so*" \
			-exec cp -a {} $(TARGET_DIR)/usr/lib/ \; ; \
	fi
	if [ -d $(@D)/usr/local/cuda-13.2/targets/aarch64-linux/lib ]; then \
		find $(@D)/usr/local/cuda-13.2/targets/aarch64-linux/lib -maxdepth 1 \( -type f -o -type l \) -name "*.so*" \
			-exec cp -a {} $(TARGET_DIR)/usr/lib/ \; ; \
	fi
	if [ -e $(@D)/usr/src/tensorrt/bin/trtexec ]; then \
		$(INSTALL) -m 0755 $(@D)/usr/src/tensorrt/bin/trtexec $(TARGET_DIR)/usr/bin/trtexec; \
	fi
	# The engine builder loads one builder-resource library per GPU
	# architecture. This board's iGPU is sm87 (Orin), which TensorRT
	# serves with the sm86 Ampere resource - there is no sm87 file, and
	# the ptx JIT fallback does not satisfy the builder ("Unable to
	# load library: libnvinfer_builder_resource_sm86" at engine build).
	# The other architectures are ~1.7 GB of dead weight.
	for f in $(TARGET_DIR)/usr/lib/libnvinfer_builder_resource_sm*.so.*; do \
		case $$f in *_sm86*) ;; *) rm -f $$f ;; esac; \
	done
endef

$(eval $(generic-package))
