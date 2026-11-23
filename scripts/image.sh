#!/usr/bin/env bash
set -euo pipefail

image="ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/$CRATE"
ref="$image:${VERSION/+/_}"
architectures='[.manifests[]? | select(.platform.os == "linux") | .platform.architecture] | sort == ["amd64","arm64"]'
inspect() { docker buildx imagetools inspect --raw "$1"; }

if ! manifest=$(inspect "$ref") || ! jq -e "$architectures" <<< "$manifest" >/dev/null; then
    ctx=$(mktemp -d)
    trap 'rm -rf -- "$ctx"' EXIT
    binary=geph5-client
    if [[ $CRATE == geph5-app ]]; then binary=geph5; fi
    for arch in amd64 arm64; do
        cpu=x86_64
        if [[ $arch == arm64 ]]; then cpu=aarch64; fi
        dir="$ctx/$arch"
        mkdir "$dir"
        gh release download "$CRATE-v$VERSION" -p "$binary-$cpu-unknown-linux-musl.tar.gz" -O - | tar -xz -C "$dir" "$binary"
        if [[ $CRATE == geph5-app ]]; then
            gh release download "geph5-client-v$CLIENT_VERSION" -p "geph5-client-$cpu-unknown-linux-musl.tar.gz" -O - | tar -xz -C "$dir" geph5-client
        fi
        docker buildx build --platform "linux/$arch" --target "$CRATE" -f Dockerfile --load -t "smoke:$arch" "$ctx"
        docker run --rm --platform "linux/$arch" "smoke:$arch" --help
    done
    docker buildx build --platform linux/amd64,linux/arm64 --target "$CRATE" -f Dockerfile \
        --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" \
        --push -t "$ref" "$ctx"
    manifest=$(inspect "$ref")
    jq -e "$architectures" <<< "$manifest" >/dev/null
fi
if ! latest=$(inspect "$image:latest") || [[ $manifest != "$latest" ]]; then
    docker buildx imagetools create -t "$image:latest" "$ref"
fi
