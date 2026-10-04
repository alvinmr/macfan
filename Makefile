.PHONY: build app dmg run test icon clean

build:            ## Compile every target (debug)
	swift build

app:              ## Build and sign build/MacFan.app (release)
	scripts/build-app.sh

dmg:              ## Universal app + DMG + SHA-256, as in a release
	UNIVERSAL=1 scripts/build-app.sh
	scripts/build-dmg.sh

run: app          ## Build the app and launch it
	open build/MacFan.app

test:             ## Run unit tests
	swift test

icon:             ## Regenerate Resources/AppIcon.icns
	scripts/make-icon.sh

clean:
	rm -rf .build build
