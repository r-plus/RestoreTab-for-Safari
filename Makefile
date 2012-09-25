ARCHS = armv7
TARGET = iphone:6.0:4.2
include theos/makefiles/common.mk

TWEAK_NAME = RestoreTabforSafari
RestoreTabforSafari_FILES = Tweak.xm
RestoreTabforSafari_FRAMEWORKS = UIKit
THEOS_INSTALL_KILL=MobileSafari

include $(THEOS_MAKE_PATH)/tweak.mk
