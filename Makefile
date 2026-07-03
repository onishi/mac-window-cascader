APP_NAME := MacWindowCascader
CONFIGURATION ?= release
# アドホック署名 (-) だと再ビルドごとに TCC のアクセシビリティ許可が失効するため、
# 使える署名 ID があればそれで署名する
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application|Apple Development/ {print $$2; exit}')
ifeq ($(strip $(CODESIGN_IDENTITY)),)
CODESIGN_IDENTITY := -
endif
BUILD_DIR := .build/$(CONFIGURATION)
APP_DIR := build/$(APP_NAME).app
INSTALL_DIR ?= $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS

.PHONY: build app install clean run

build:
	swift build -c $(CONFIGURATION)

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	chmod +x "$(MACOS_DIR)/$(APP_NAME)"
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)"
	@echo "Created $(APP_DIR) (signed as: $(CODESIGN_IDENTITY))"

run: app
	open "$(APP_DIR)"

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(APP_DIR)" "$(INSTALLED_APP)"
	open "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"

clean:
	rm -rf .build build
