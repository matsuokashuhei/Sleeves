DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
MACOS_DIR     := apps/macos
PROJECT       := $(MACOS_DIR)/Sleeves.xcodeproj
DERIVED_DATA  := .build
APP_PATH      := $(DERIVED_DATA)/Build/Products/Debug/Sleeves.app

.PHONY: gen build test run logs

gen:
	cd $(MACOS_DIR) && DEVELOPER_DIR=$(DEVELOPER_DIR) xcodegen generate

build:
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project $(PROJECT) -scheme Sleeves -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) build

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project $(PROJECT) -scheme Sleeves -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) test

run:
	pkill -x Sleeves || true
	open $(APP_PATH)

logs:
	/usr/bin/log show --last 5m --style compact --info \
		--predicate 'subsystem == "com.cacheandbuffer.Sleeves"'
