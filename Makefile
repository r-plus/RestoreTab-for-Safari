include theos/makefiles/common.mk

TWEAK_NAME = RestoreTabforSafari
RestoreTabforSafari_FILES = Tweak.xm
RestoreTabforSafari_FRAMEWORKS = UIKit
#ADDITIONAL_LDFLAGS = libsubjc.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
