# Geph5 autobuild

This repository checks crates.io daily for new stable releases of `geph5-client` and `geph5-app` and publishes Windows and Linux musl binaries to [GitHub Releases](https://github.com/touhoured/geph5/releases).

## Containers

Both images support Linux AMD64 and ARM64. Use `latest` or an exact crate version such as `0.5.5`. The app image includes the client executable used by its manager.

```sh
docker run --rm ghcr.io/touhoured/geph5-client:latest --help
docker run --rm ghcr.io/touhoured/geph5-app:latest --help
```

## OpenWrt

Download the matching `geph5-client` package from GitHub Releases. Check your router’s package architecture with `opkg print-architecture` on OpenWrt 24.10 or `apk --print-arch` on 25.12. Choose `x86_64` or `aarch64_generic` as reported by the router.

Run the command for your release in the download directory. The local APK requires `--allow-untrusted` because the OpenWrt release keys do not sign it.

```sh
# OpenWrt 24.10
opkg install ./geph5-client-v*-r1-*.ipk

# OpenWrt 25.12
apk add --allow-untrusted ./geph5-client-v*-r1-*.apk
```

Run `geph5-client --help` to see the configuration options.
