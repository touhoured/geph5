#!/usr/bin/env bash
set -euo pipefail

targets=(i686-pc-windows-msvc x86_64-pc-windows-msvc x86_64-unknown-linux-musl aarch64-unknown-linux-musl)
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
    local repo published crate version released
    repo=$(repository)
    published=$(published_tags "$repo")
    for crate in geph5-client geph5-app; do
        version=$(curl -fsS -A "Geph5 autobuild (https://github.com/$repo)" \
            "https://crates.io/api/v1/crates/$crate?include=default_version" |
            jq -r '.versions[0] | select(.yanked == false) | .num')
        [[ $version =~ $stable_version ]] || continue
        released=false
        if grep -Fxq "$crate-v$version" <<< "$published"; then released=true; fi
        jq -nc --arg crate "$crate" --arg version "$version" --argjson released "$released" '{$crate, $version, $released}'
    done | jq -cs .
}

asset_name() {
    local binary=$1 target=$2
    case "$target" in
        *-windows-msvc) echo "$binary-$target.zip" ;;
        *) echo "$binary-$target.tar.gz" ;;
    esac
}

build() (
    local crate=$1 version=$2 target=$3
    local binary directory="dist/$crate-v$version" asset staging
    binary=$(package_binary "$crate" "$version")
    asset=$(asset_name "$binary" "$target")
    mkdir -p "$directory"
    staging=$(mktemp -d "$PWD/$directory/.build.XXXXXXXX")
    trap 'rm -rf -- "$staging"' EXIT
    if [[ $target == *-windows-msvc ]]; then
        rustup target add "$target"
        RUSTFLAGS="-C target-feature=+crt-static" cargo install --no-track \
            --version "=$version" --target "$target" --bin "$binary" --root "$staging" "$crate"
        python -m zipfile -c "$staging/$asset" "$staging/bin/$binary.exe"
    else
        curl -fsSL "https://static.crates.io/crates/$crate/$crate-$version.crate" | tar -xz -C "$staging"
        (
            cd "$staging/$crate-$version"
            cross build --release --target "$target" --target-dir target --bin "$binary"
            tar -czf "$staging/$asset" -C "target/$target/release" "$binary"
        )
    fi
    mv -f -- "$staging/$asset" "$directory/$asset"
    echo "$directory/$asset"
)

release_notes() {
    local crate=$1 version=$2 upstream=https://github.com/geph-official/geph5
    local refs ref tag previous=
    refs=$(git ls-remote --refs --sort=version:refname "$upstream" "refs/tags/$crate-v*") || return
    while read -r _ ref; do
        tag=${ref#refs/tags/}
        [[ ${tag#"$crate-v"} =~ $stable_version ]] || continue
        if [[ $tag == "$crate-v$version" ]]; then
            if [[ -n $previous ]]; then
                echo "[Upstream changes]($upstream/compare/$previous...$tag)"
            else
                echo "[Upstream source]($upstream/tree/$tag)"
            fi
            return
        fi
        previous=$tag
    done <<< "$refs"
    echo "https://crates.io/crates/$crate/$version"
}

release() {
    local crate=$1 version=$2
    local tag="$crate-v$version" binary repo published target path notes
    local -a files=() target_args=()
    binary=$(package_binary "$crate" "$version")
    repo=$(repository)
    published=$(published_tags "$repo")
    if grep -Fxq "$tag" <<< "$published"; then
        echo "Already published: $tag"
        return
    fi

    for target in "${targets[@]}"; do
        path="dist/$tag/$(asset_name "$binary" "$target")"
        [[ -s $path && -f $path ]] || fail "Missing archive: $path"
        files+=("$path")
    done
    if [[ -n ${GITHUB_SHA:-} ]]; then target_args=(--target "$GITHUB_SHA"); fi
    notes=$(release_notes "$crate" "$version")
    gh release create "$tag" "${files[@]}" --repo "$repo" --title "$tag" \
        --notes "$notes" "${target_args[@]}"
}

case "${1:-}/$#" in
    check/1) check ;;
    build/4) build "$2" "$3" "$4" ;;
    release/3) release "$2" "$3" ;;
    *) fail "Usage: $0 check | build CRATE VERSION TARGET | release CRATE VERSION" ;;
esac
