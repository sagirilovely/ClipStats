APP_NAME  := ClipStats
APP_ID    := local.sagiri.clipstats
BUILD_DIR := build
BUNDLE    := $(BUILD_DIR)/$(APP_NAME).app
BIN       := $(BUILD_DIR)/$(APP_NAME)

SOURCES := $(shell find Sources -name '*.swift')
SWIFTC  := swiftc
FLAGS   := -O -swift-version 5 -module-cache-path $(BUILD_DIR)/mcache -target arm64-apple-macos13.0

.PHONY: all bundle build run install uninstall clean icon

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

clean:
	@rm -rf $(BUILD_DIR)

icon:
	@$(MAKE) -s -f Makefile icon-internal || true
