SCHEME := Rum
PROJECT := Rum.xcodeproj

# PROFILE=name builds a copy of Rum with its own bundle ID (com.adrianlungu.rum.profile.name), so
# its settings, bottle list, bottles, Wine installs and macOS permissions are separate from yours.
# Example: make run PROFILE=fresh    ·    make profile-reset PROFILE=fresh    ·    make profiles
PROFILE ?=
ifneq ($(PROFILE),)
  ifneq ($(shell echo '$(PROFILE)' | grep -E '^[A-Za-z0-9-]+$$'),$(PROFILE))
    $(error PROFILE may only contain letters, digits and dashes)
  endif
  PROFILE_ID := com.adrianlungu.rum.profile.$(PROFILE)
  PROFILE_FLAGS := RUM_PROFILE_SUFFIX=.profile.$(PROFILE)
  DERIVED := build/profiles/$(PROFILE)
else
  DERIVED := build
endif
APP_DEBUG := $(DERIVED)/Build/Products/Debug/Rum.app
APP_RELEASE := $(DERIVED)/Build/Products/Release/Rum.app
BIN_DEBUG := $(APP_DEBUG)/Contents/MacOS/Rum
VERSION ?= $(or $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'),1.1.0)

SHELL := /bin/bash
XCBEAUTIFY := $(shell command -v xcbeautify)

.PHONY: build build-release run debug lint test graphics-canary clean kill site profiles profile-reset

build:
	set -o pipefail; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) MARKETING_VERSION=$(VERSION) $(PROFILE_FLAGS) build $(if $(XCBEAUTIFY),| xcbeautify,)

build-release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) MARKETING_VERSION=$(VERSION) build

run: build
	open -n "$(APP_DEBUG)"

# Launch attached so print/NSLog goes to the terminal. Ctrl-C to quit.
debug: build
	$(BIN_DEBUG)

lint:
	swiftlint --strict

test:
	swift test --package-path RumKit

graphics-canary:
	./scripts/graphics-canary.sh

kill:
	-pkill -x Rum

clean:
	rm -rf $(DERIVED)

# Preview the website in docs/ at http://localhost:8000 (Ctrl-C to stop).
site:
	python3 -m http.server 8000 --directory docs

# List profiles that have been built.
profiles:
	@ls build/profiles 2>/dev/null || echo "No profiles yet. Try: make run PROFILE=fresh"

# Wipe a profile's data (settings, bottle list, bottles, Wine) so its next launch is a first launch.
# Never touches your normal Rum data.
profile-reset:
	@test -n "$(PROFILE)" || { echo "Usage: make profile-reset PROFILE=name"; exit 1; }
	-pkill -f "build/profiles/$(PROFILE)/Build/Products/Debug/Rum.app/"
	-defaults delete "$(PROFILE_ID)" 2>/dev/null
	@# macOS won't let the container folder or its metadata file be deleted; empty everything else.
	-find "$(HOME)/Library/Containers/$(PROFILE_ID)" -mindepth 1 -maxdepth 1 \
		! -name .com.apple.containermanagerd.metadata.plist -exec rm -rf {} +
	rm -rf "$(HOME)/Library/Application Support/$(PROFILE_ID)" "$(HOME)/Library/Logs/$(PROFILE_ID)"
	-tccutil reset All "$(PROFILE_ID)"
	@echo "Reset profile $(PROFILE)."
