PLATFORM_IOS = iOS Simulator,name=iPad mini (A17 Pro)
IOS_SIM = 8C8C409E-EDE8-4AC3-969D-449731DC9DA1
PLATFORM_MACOS = macOS
SCHEME = DSPHeaders
XCCOV = xcrun xccov view --report --only-targets
WORKSPACE = $(PWD)/.workspace
BUILD_FLAGS = -skipMacroValidation \
			  -skipPackagePluginValidation \
			  -enableCodeCoverage YES \
			  -scheme $(SCHEME) \
			  -clonedSourcePackagesDirPath "$(WORKSPACE)"

ifeq ($(GITHUB_ENV),)
XCB = | xcbeautify --renderer github-actions
endif

default: report

report: percentage-iOS percentage-macOS
	@if [[ -n "$$GITHUB_ENV" ]]; then \
        echo "PERCENTAGE=$$(< percentage_macOS.txt)" >> $$GITHUB_ENV; \
    fi

percentage-iOS: coverage-iOS
	awk '/ DSPHeaders / { print $$4 }' coverage_iOS.txt > percentage_iOS.txt
	echo "iOS Coverage Pct:"
	cat percentage_iOS.txt

percentage-macOS: coverage-macOS
	awk '/ DSPHeaders / { print $$4 }' coverage_macOS.txt > percentage_macOS.txt
	echo "macOS Coverage Pct:"
	cat percentage_macOS.txt

coverage-iOS: test-iOS
	$(XCCOV) $(PWD)/.DerivedData-iOS/Logs/Test/*.xcresult > coverage_iOS.txt
	echo "iOS Coverage:"
	cat coverage_iOS.txt

coverage-macOS: test-macOS
	$(XCCOV) $(PWD)/.DerivedData-macOS/Logs/Test/*.xcresult > coverage_macOS.txt
	echo "macOS Coverage:"
	cat coverage_macOS.txt

test-iOS: clean
	rm -rf "$(PWD)/.DerivedData-iOS"
	USE_UNSAFE_FLAGS="1" set -o pipefail && xcodebuild test \
		$(BUILD_FLAGS) \
		-derivedDataPath "$(PWD)/.DerivedData-iOS" \
		-destination platform="$(PLATFORM_IOS)" \
		$(XCB)

test-macOS:
	rm -rf "$(PWD)/.DerivedData-macOS"
	USE_UNSAFE_FLAGS="1" xcodebuild test \
		$(BUILD_FLAGS) \
		-derivedDataPath "$(PWD)/.DerivedData-macOS" \
		-destination platform="$(PLATFORM_MACOS)" \
		$(XCB)

.PHONY: report test-iOS test-macOS coverage-iOS coverage-macOS coverage-iOS percentage-macOS percentage-iOS

clean:
	-rm -rf $(PWD)/.DerivedData-* "$(WORKSPACE)" coverage*.txt percentage*.txt
