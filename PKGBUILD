# Maintainer: relya <relya@tuta.io>
pkgname=openremote
pkgver=0.1
pkgrel=1
pkgdesc="Wireless virtual Xbox 360 controller host for Linux"
arch=('x86_64')
url="https://github.com/relyay/OpenRemote"
license=('MIT')
depends=('glibc')
makedepends=('go')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('31d5bc879539fb00d02571db42966280b5c9854aa924c906d3c29e652088c21e')

prepare() {
	cd "OpenRemote-$pkgver"
	go mod download
}

build() {
	cd "OpenRemote-$pkgver"
	export CGO_ENABLED=0
	export GOFLAGS="-mod=mod -trimpath"
	go build -o openremote .
}

package() {
	cd "OpenRemote-$pkgver"
	install -Dm755 openremote "$pkgdir/usr/bin/openremote"
	install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
