go := env_var_or_default("GO", "go")
xtool := env_var_or_default("XTOOL", "xtool")
dist := "dist"

default: linux

linux:
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 {{go}} build -o {{dist}}/openremote-linux-amd64 .

windows:
    CGO_ENABLED=0 GOOS=windows GOARCH=amd64 {{go}} build -o {{dist}}/openremote-windows-amd64.exe .

macos:
    CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 {{go}} build -o {{dist}}/openremote-macos-arm64 .

ios:
    cd ios && {{xtool}} dev build -c release --ipa
    mkdir -p {{dist}}
    cp -f ios/xtool/OpenRemote.ipa {{dist}}/OpenRemote.ipa

clean:
    rm -rf {{dist}}
    
