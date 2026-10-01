ARCHS = arm64 arm64e
TARGET = iphoneos
SDKVERSION = 16.7
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCam
VCam_FILES = Tweak.x
VCam_FRAMEWORKS = UIKit AVFoundation CoreVideo CoreMedia
VCam_CFLAGS = -fobjc-arc -Wall -Wextra -O2

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	@mkdir -p $(THEOS_STAGING_DIR)/var/mobile/Library/Preferences/VCam
	@mkdir -p $(THEOS_STAGING_DIR)/var/mobile/Library/Preferences/VCam/input_media
	@install -d $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries
	@echo "VCam tweak staged for rootless deployment."
