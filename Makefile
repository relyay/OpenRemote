.PHONY: linux windows macos ios clean

GO ?= go
XTOOL ?= xtool
DIST := dist

.DEFAULT_GOAL := linux

linux:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -o $(DIST)/openremote-linux-amd64 .

windows:
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 $(GO) build -o $(DIST)/openremote-windows-amd64.exe .

macos:
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 $(GO) build -o $(DIST)/openremote-macos-arm64 .

ios:
	cd ios && $(XTOOL) dev build -c release --ipa
	cp -f ios/xtool/OpenRemote.ipa dist/OpenRemote.ipa

clean:
	rm -rf $(DIST)
