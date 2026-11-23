#!/usr/bin/env bash
set -euo pipefail

case "$ARCH" in
    x86_64) target=x86/64; cpu=x86_64 ;;
    aarch64_generic) target=armsr/armv8; cpu=aarch64 ;;
    *) exit 1 ;;
esac
case "$SERIES" in
    24.10.6) format=ipk ;;
    25.12.6) format=apk ;;
    *) exit 1 ;;
esac

tag="geph5-client-v$VERSION"
asset="${tag}-r1-${ARCH}.$format"
assets=$(gh release view "$tag" --json assets --jq '.assets[].name')
if grep -Fxq "$asset" <<< "$assets"; then exit 0; fi

work=$(mktemp -d)
trap 'sudo rm -rf -- "$work"' EXIT
cp openwrt/Makefile "$work/"
gh release download "$tag" -p "geph5-client-$cpu-unknown-linux-musl.tar.gz" -D "$work"
cd "$work"
base="https://downloads.openwrt.org/releases/$SERIES/targets/$target"
curl -fsSLO "$base/sha256sums"
sdk=$(awk '$2 ~ /^\*openwrt-sdk-.*\.tar\.zst$/ {print substr($2,2)}' sha256sums)
rootfs="openwrt-$SERIES-${target/\//-}-rootfs.tar.gz"
for file in "$sdk" "$rootfs"; do
    curl -fsSLO "$base/$file"
    awk -v name="*$file" '$2 == name' sha256sums | sha256sum -c -
done
mkdir sdk rootfs
tar -xf "$sdk" --strip-components=1 -C sdk
pkg=sdk/package/geph5-client
mkdir -p "$pkg"
cp Makefile "$pkg/"
tar -xzf "geph5-client-$cpu-unknown-linux-musl.tar.gz" -C "$pkg" geph5-client
export GEPH_VERSION=${VERSION%%+*}
if ! command -v gawk >/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y gawk
fi
make -C sdk defconfig
make -C sdk package/geph5-client/compile GEPH_VERSION="$GEPH_VERSION" V=s
mapfile -t packages < <(find sdk/bin -type f -name "geph5-client*.$format")
[[ ${#packages[@]} == 1 ]]
cp "${packages[0]}" "$asset"

sudo tar -xzf "$rootfs" -C rootfs
sudo mkdir -p rootfs/tmp/lock
sudo cp "$asset" "rootfs/tmp/package.$format"
if [[ $format == apk ]]; then
    sudo chroot rootfs /usr/bin/apk add --no-network --allow-untrusted /tmp/package.apk
else
    sudo chroot rootfs /bin/opkg install /tmp/package.ipk
fi
sudo chroot rootfs /usr/bin/geph5-client --help
gh release upload "$tag" "$asset" --repo "$GITHUB_REPOSITORY"
