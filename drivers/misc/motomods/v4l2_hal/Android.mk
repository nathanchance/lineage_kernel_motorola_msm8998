LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := v4l2_hal
LOCAL_MODULE_TAGS := optional
LOCAL_ADDITIONAL_DEPENDENCIES := build-local
include $(BUILD_PHONY_PACKAGE)

LCL_SRC_PATH := $(LOCAL_PATH)
LCL_KDIRARG := KERNELDIR="${ANDROID_PRODUCT_OUT}/obj/KERNEL_OBJ"
ifeq ($(TARGET_ARCH),arm64)
  LCL_KERNEL_TOOLS_PREFIX=aarch64-linux-android-
else
  LCL_KERNEL_TOOLS_PREFIX:=arm-linux-androideabi-
endif
LCL_ARCHARG := ARCH=$(TARGET_ARCH)
LCL_FLAGARG := EXTRA_CFLAGS+=-fno-pic
LCL_ARGS := $(LCL_KDIRARG) $(LCL_ARCHARG) $(LCL_FLAGARG)

#Create vendor/lib/modules directory if it doesn't exist
$(shell mkdir -p $(TARGET_OUT_VENDOR)/lib/modules)

ifeq ($(GREYBUS_DRIVER_INSTALL_TO_KERNEL_OUT),true)
V4L2_HAL_MODULES_OUT := $(KERNEL_MODULES_OUT)
else
V4L2_HAL_MODULES_OUT := $(TARGET_OUT_VENDOR)/lib/modules/
endif

# To ensure KERNEL_OUT and TARGET_PREBUILT_INT_KERNEL are defined,
# kernel/AndroidKernel.mk must be included. While m and regular
# make builds will include kernel/AndroidKernel.mk, mm and mmm builds
# do not. Therefore, we need to explicitly include kernel/AndroidKernel.mk.
# It is safe to include it more than once because the entire file is
# guarded by "ifeq ($(TARGET_PREBUILT_KERNEL),) ... endif".
TARGET_KERNEL_PATH := $(TARGET_KERNEL_SOURCE)/AndroidKernel.mk
include $(TARGET_KERNEL_PATH)

# Simply copy the kernel module from where the kernel build system
# created it to the location where the Android build system expects it.
# If LOCAL_MODULE_DEBUG_ENABLE is set, strip debug symbols. So that,
# the final images generated by ABS will have the stripped version of
# the modules
ifeq ($(TARGET_KERNEL_VERSION),3.18)
  MODULE_SIGN_FILE := perl ./$(TARGET_KERNEL_SOURCE)/scripts/sign-file
  MODSECKEY := $(KERNEL_OUT)/signing_key.priv
  MODPUBKEY := $(KERNEL_OUT)/signing_key.x509
else
  MODULE_SIGN_FILE := $(KERNEL_OUT)/scripts/sign-file
  MODSECKEY := $(KERNEL_OUT)/certs/signing_key.pem
  MODPUBKEY := $(KERNEL_OUT)/certs/signing_key.x509
endif

ifeq ($(GREYBUS_KERNEL_MODULE_SIG), true)
build-local: $(INSTALLED_KERNEL_TARGET) | $(ACP)
	@mkdir -p $(V4L2_HAL_MODULES_OUT)
	$(MAKE) clean -C $(LCL_SRC_PATH)
	$(MAKE) -j$(MAKE_JOBS) -C $(LCL_SRC_PATH) CROSS_COMPILE=$(LCL_KERNEL_TOOLS_PREFIX) $(LCL_ARGS)
	ko=`find $(LCL_SRC_PATH) -type f -name "*.ko"`;\
	for i in $$ko;\
	do sh -c "\
	   KMOD_SIG_ALL=`cat $(KERNEL_OUT)/.config | grep CONFIG_MODULE_SIG_ALL | cut -d'=' -f2`; \
	   KMOD_SIG_HASH=`cat $(KERNEL_OUT)/.config | grep CONFIG_MODULE_SIG_HASH | cut -d'=' -f2 | sed 's/\"//g'`; \
	   if [ \"\$$KMOD_SIG_ALL\" = \"y\" ] && [ -n \"\$$KMOD_SIG_HASH\" ]; then \
	      echo \"Signing greybus module: \" `basename $$i`; \
	      $(MODULE_SIGN_FILE) \$$KMOD_SIG_HASH $(MODSECKEY) $(MODPUBKEY) $$i; \
	   fi; \
	"\
	$(LCL_KERNEL_TOOLS_PREFIX)strip --strip-unneeded $$i;\
	$(ACP) -fp $$i $(V4L2_HAL_MODULES_OUT);\
	done
else
build-local: $(ACP) $(INSTALLED_KERNEL_TARGET)
	$(MAKE) clean -C $(LCL_SRC_PATH)
	$(MAKE) -j$(MAKE_JOBS) -C $(LCL_SRC_PATH) CROSS_COMPILE=$(LCL_KERNEL_TOOLS_PREFIX) $(LCL_ARGS)
	ko=`find $(LCL_SRC_PATH) -type f -name "*.ko"`;\
	for i in $$ko;\
	do $(LCL_KERNEL_TOOLS_PREFIX)strip --strip-unneeded $$i;\
	$(ACP) -fp $$i $(V4L2_HAL_MODULES_OUT);\
	done
endif
