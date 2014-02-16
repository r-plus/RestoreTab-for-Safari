export GO_EASY_ON_ME=1
ARCHS = armv7 arm64
TARGET = iphone:clang::4.2
include theos/makefiles/common.mk

TWEAK_NAME = RestoreTabforSafari
RestoreTabforSafari_FILES = Tweak.xm
RestoreTabforSafari_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 MobileSafari"
