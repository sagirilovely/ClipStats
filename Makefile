APP_NAME  := ClipStats
APP_ID    := local.sagiri.clipstats
BUILD_DIR := build
BUNDLE    := $(BUILD_DIR)/$(APP_NAME).app
BIN       := $(BUILD_DIR)/$(APP_NAME)

SOURCES := $(shell find Sources -name '*.swift')
SWIFTC  := swiftc
ARCH    ?= $(shell uname -m)
FLAGS   := -O -swift-version 5 -module-cache-path $(BUILD_DIR)/mcache -target $(ARCH)-apple-macos13.0

.PHONY: all build bundle run install uninstall package dmg clean icon

all: bundle

build: $(BIN)

$(BIN): $(SOURCES) Makefile
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(FLAGS) $(SOURCES) -o $(BIN)

bundle: $(BIN)
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/; fi
	@codesign --force --sign - --timestamp=none $(BUNDLE)
	@echo "built $(BUNDLE)"

run: bundle
	@pkill -f '$(APP_NAME).app/Contents/MacOS' 2>/dev/null || true
	@open $(BUNDLE)

install: bundle
	@pkill -f '$(APP_NAME).app/Contents/MacOS' 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(BUNDLE) /Applications/
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
