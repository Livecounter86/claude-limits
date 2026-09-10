# XCTest/swift-testing live in the Xcode toolchain, not in CommandLineTools,
# so `make test` needs Xcode. Pinning DEVELOPER_DIR also keeps build and test on
# one toolchain -- mixing them corrupts .build with modules from two Swift
# versions. Building the app itself works with CommandLineTools alone, so the
# pin is applied only when Xcode is actually installed.
XCODE := /Applications/Xcode.app/Contents/Developer
ifneq ($(wildcard $(XCODE)),)
export DEVELOPER_DIR := $(XCODE)
endif

APP := ClaudeLimits.app
BIN := .build/release/ClaudeLimitsApp

.PHONY: test build app install uninstall run clean

test:
	@test -d "$(XCODE)" || { echo "make test needs Xcode.app (CommandLineTools has no XCTest)"; exit 1; }
	swift test

build:
	swift build -c release

## Package the release binary into a menu-bar .app bundle.
app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp $(BIN) $(APP)/Contents/MacOS/ClaudeLimits
	codesign --force --sign - $(APP)
	@echo "built $(APP)"

## Copy into /Applications and launch.
install: app
	pkill -x ClaudeLimits || true
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/
	open /Applications/$(APP)
	@echo "installed and launched"

uninstall:
	pkill -x ClaudeLimits || true
	rm -rf /Applications/$(APP)

## Launch from the build directory without installing.
run: app
	pkill -x ClaudeLimits || true
	open $(APP)

clean:
	rm -rf .build $(APP)
