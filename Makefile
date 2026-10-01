TARGET := iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := VCamTweak
VCamTweak_FILES := Tweak.x
VCamTweak_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME := VCamApp
VCamApp_FILES := ContentView.swift
VCamApp_FRAMEWORKS := UIKit SwiftUI PhotosUI AVFoundation
VCamApp_SWIFTFLAGS := -parse-as-library
VCamApp_INSTALL_PATH := /Applications

include $(THEOS_MAKE_PATH)/application.mk