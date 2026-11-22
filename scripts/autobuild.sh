#!/usr/bin/env bash
set -euo pipefail

platforms=(windows-x86 windows-x64 linux-musl-x64 linux-musl-arm64)
stable_version='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

fail() { echo "$*" >&2; exit 1; }

package_binary() {
    local crate=$1 version=$2
    [[ $version =~ $stable_version ]] || fail "Expected an exact stable version: $version"
    case "$crate" in
        geph5-client) echo geph5-client ;;
        geph5-app) echo geph5 ;;
        *) fail "Unknown crate: $crate" ;;
    esac
}

repository() {
    if [[ -n ${GITHUB_REPOSITORY:-} ]]; then
        echo "$GITHUB_REPOSITORY"
    else
        gh repo view --json nameWithOwner --jq .nameWithOwner
    fi
}

published_tags() {
    gh api --paginate "repos/$1/releases?per_page=100" --jq '.[] | select(.draft == false) | .tag_name'
}

check() {
    local repo published crate version
    repo=$(repository)
    published=$(published_tags "$repo")
    for crate in geph5-client geph5-app; do
        version=$(curl -fsS -A "Geph5 autobuild (https://github.com/$repo)" \
            "https://crates.io/api/v1/crates/$crate?include=default_version" |
            jq -r '.versions[0] | select(.yanked == false) | .num')
        [[ $version =~ $stable_version ]] || continue
        grep -Fxq "$crate-v$version" <<< "$published" && continue
        jq -nc --arg crate "$crate" --arg version "$version" '{$crate, $version}'
    done | jq -cs .
}

asset_name() {
    local binary=$1 platform=$2
    case "$platform" in
        windows-*) echo "$binary-$platform.zip" ;;
        *) echo "$binary-$platform.tar.gz" ;;
    esac
}

build() (
    local crate=$1 version=$2 platform=$3
    local binary directory="dist/$crate-v$version" target image asset staging
    binary=$(package_binary "$crate" "$version")
    case "$platform" in
        windows-x86) target=i686-pc-windows-msvc ;;
        windows-x64) target=x86_64-pc-windows-msvc ;;
        linux-musl-x64) target=x86_64-unknown-linux-musl ;;
        linux-musl-arm64) target=aarch64-unknown-linux-musl ;;
        *) fail "Unknown platform: $platform" ;;
    esac
    asset=$(asset_name "$binary" "$platform")
    mkdir -p "$directory"
    staging=$(mktemp -d "$PWD/$directory/.build.XXXXXXXX")
    trap 'rm -rf -- "$staging"' EXIT
    mkdir "$staging/bin"
    local -a cargo_args=(install --locked --no-track --version "=$version" --target "$target" --bin "$binary" "$crate")
    if [[ $platform == windows-* ]]; then
        rustup target add "$target"
        RUSTFLAGS="-C target-feature=+crt-static" cargo "${cargo_args[@]}" --root "$staging"
        python -m zipfile -c "$staging/$asset" "$staging/bin/$binary.exe"
    else
        image="ghcr.io/rust-cross/rust-musl-cross:${target%%-*}-musl"
        "${CONTAINER_ENGINE:-docker}" run --rm -v "$staging:/out" \
            "$image" cargo "${cargo_args[@]}" --root /out
        tar -czf "$staging/$asset" -C "$staging/bin" "$binary"
    fi
    mv -f -- "$staging/$asset" "$directory/$asset"
    echo "$directory/$asset"
)

release() {
    local crate=$1 version=$2
    local tag="$crate-v$version" binary repo published platform path
    local -a files=() target_args=()
    binary=$(package_binary "$crate" "$version")
    repo=$(repository)
    published=$(published_tags "$repo")
    if grep -Fxq "$tag" <<< "$published"; then
        echo "Already published: $tag"
        return
    fi

    for platform in "${platforms[@]}"; do
        path="dist/$tag/$(asset_name "$binary" "$platform")"
        [[ -s $path && -f $path ]] || fail "Missing archive: $path"
        files+=("$path")
    done
    if [[ -n ${GITHUB_SHA:-} ]]; then target_args=(--target "$GITHUB_SHA"); fi
    gh release create "$tag" "${files[@]}" --repo "$repo" --title "$tag" \
        --notes "https://crates.io/crates/$crate/$version" "${target_args[@]}"
}

case "${1:-}/$#" in
    check/1) check ;;
    build/4) build "$2" "$3" "$4" ;;
    release/3) release "$2" "$3" ;;
    *) fail "Usage: $0 check | build CRATE VERSION PLATFORM | release CRATE VERSION" ;;
esac
