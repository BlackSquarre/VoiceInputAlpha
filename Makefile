APP_NAME = VoiceInput
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR = /Applications

.PHONY: build run install clean

build:
	swift build -c release
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Sources/VoiceInput/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Sources/VoiceInput/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	cp -R Resources/*.lproj "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --sign - --entitlements VoiceInput.entitlements "$(APP_BUNDLE)"
	@echo "Built: $(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

install: build
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf .build
