APP_NAME  := ClipStats
APP_ID    := local.sagiri.clipstats
BUILD_DIR := build
BUNDLE    := $(BUILD_DIR)/$(APP_NAME).app
BIN       := $(BUILD_DIR)/$(APP_NAME)
APPEX_NAME := ClipStatsFinder
APPEX_BIN := $(BUILD_DIR)/appex/$(APPEX_NAME)
APPEX_SRC := $(wildcard Sources/FinderExt/*.swift)
APPEX_DIR := $(BUNDLE)/Contents/PlugIns/$(APPEX_NAME).appex

SOURCES := $(shell find Sources -name '*.swift' -not -path 'Sources/FinderExt/*')
SWIFTC  := swiftc
ARCH    ?= $(shell uname -m)
FLAGS   := -O -swift-version 5 -module-cache-path $(BUILD_DIR)/mcache -target $(ARCH)-apple-macos13.0 -framework FinderSync

.PHONY: all build bundle run install uninstall package dmg clean icon

all: bundle

build: $(BIN)

$(BIN): $(SOURCES) Makefile
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(FLAGS) $(SOURCES) -o $(BIN)

$(APPEX_BIN): $(APPEX_SRC) scripts/build-appex.sh
	@mkdir -p $(BUILD_DIR)/appex
	@./scripts/build-appex.sh $(ARCH) $(APPEX_BIN)

bundle: $(BIN) $(APPEX_BIN)
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources $(APPEX_DIR)/Contents/MacOS
	@cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/; fi
	@cp $(APPEX_BIN) $(APPEX_DIR)/Contents/MacOS/$(APPEX_NAME)
	@cp Resources/FinderExt-Info.plist $(APPEX_DIR)/Contents/Info.plist
	@codesign --force --sign - --timestamp=none --entitlements Resources/FinderExt.entitlements $(APPEX_DIR)
	@codesign --force --sign - --timestamp=none $(BUNDLE)
	@echo "built $(BUNDLE)"

run: bundle
	@pkill -f '$(APP_NAME).app/Contents/MacOS' 2>/dev/null || true
	@open $(BUNDLE)

install: bundle
	@pkill -f '$(APP_NAME).app/Contents/MacOS' 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(BUNDLE) /Applications/
	@pluginkit -a /Applications/$(APP_NAME).app/Contents/PlugIns/$(APPEX_NAME).appex 2>/dev/null || true
	@open /Applications/$(APP_NAME).app
	@echo "installed to /Applications/$(APP_NAME).app"

uninstall:
	@pkill -f '$(APP_NAME).app/Contents/MacOS' 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME).app

# 生成发布产物（默认通用二进制）：dist/ClipStats-<版本>-macos-<架构>.{zip,dmg}
package:
	@ARCH=$(ARCH) ./scripts/package.sh

clean:
	@rm -rf $(BUILD_DIR)

# 应用图标：以根目录 logo.svg 为唯一来源，栅格化后打包成 AppIcon.icns
icon:
	@mkdir -p $(BUILD_DIR)
	@$(SWIFTC) -module-cache-path $(BUILD_DIR)/mcache scripts/make-icon.swift -o $(BUILD_DIR)/make-icon
	@$(BUILD_DIR)/make-icon logo.svg Resources
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "icon rebuilt: Resources/AppIcon.icns"
