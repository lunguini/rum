SCHEME := Whisky
PROJECT := Rum.xcodeproj
DERIVED := build
APP_DEBUG := $(DERIVED)/Build/Products/Debug/Rum.app
APP_RELEASE := $(DERIVED)/Build/Products/Release/Rum.app
BIN_DEBUG := $(APP_DEBUG)/Contents/MacOS/Whisky

SHELL := /bin/bash
XCBEAUTIFY := $(shell command -v xcbeautify)

.PHONY: build build-release run debug lint test graphics-canary clean kill

build:
	set -o pipefail; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build $(if $(XCBEAUTIFY),| xcbeautify,)

build-release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build

run: build
	open $(APP_DEBUG)

# Launch attached so print/NSLog goes to the terminal. Ctrl-C to quit.
debug: build
	$(BIN_DEBUG)

lint:
	swiftlint --strict

test:
	swift test --package-path WhiskyKit

graphics-canary:
	./scripts/graphics-canary.sh

kill:
	-pkill -x Whisky

clean:
	rm -rf $(DERIVED)
