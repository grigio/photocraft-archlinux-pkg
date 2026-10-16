#!/usr/bin/env bash
# Build one photocraft Arch package from an upstream tag release, compiling the
# Rust workspace from source.
#
# Usage: build-package.sh <tag> <arch>
#   e.g. build-package.sh v0.9.0 x86_64
#
# Must run inside an Arch Linux environment (the CI job uses the official
# archlinux:base-devel container) as an unprivileged user; makepkg uses fakeroot
# for the packaging phase.
set -euo pipefail

tag=${1:?usage: build-package.sh <tag> <arch>}
arch=${2:?usage: build-package.sh <tag> <arch>}

case "$arch" in
	x86_64 | aarch64 | riscv64) ;;
	*) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac

# Arch pkgver must not contain hyphens. v0.1.1-rc.5 becomes 0.1.1rc.5, which
# also sorts correctly (before 0.1.1) with vercmp. Only upstream's prerelease
# form is supported; a plain "-N" suffix would be ambiguous (1.2.3-1 would
# collapse to 1.2.31, which sorts *after* 1.2.3), so it is rejected.
if [[ $tag =~ -[0-9]+$ ]]; then
	echo "unsupported version form '$tag': expected e.g. vX.Y.Z or vX.Y.Z-rc.N" >&2
	exit 1
fi
pkgver=$(printf '%s' "${tag#v}" | sed -E 's/-([A-Za-z]+)\.([0-9]+)$/\1.\2/')
case "$pkgver" in
	*-*)
		echo "could not normalise '$tag' into an Arch pkgver" >&2
		exit 1
		;;
esac

# Resolve the tag to a commit. Upstream publishes checksums only for its release
# assets, not for source tarballs, and GitHub's auto-generated archives are not
# guaranteed byte-stable -- so the tag is cloned and its commit verified in the
# PKGBUILD's prepare() instead.
commit=$(curl -fsSL \
	-H 'Accept: application/vnd.github+json' \
	"https://api.github.com/repos/storytold/photocraft/commits/${tag}" |
	jq -r '.sha // empty')

if [ -z "$commit" ]; then
	echo "'$tag' does not resolve to an upstream commit" >&2
	exit 2 # exit 2 lets the caller skip it without failing the matrix
fi

REPO_DIR=${REPO_DIR:-/repo/out}
PKGBUILD_TPL="$(dirname "$(readlink -f "$0")")/PKGBUILD.in"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

echo ">> building photocraft ${pkgver}-1 for ${arch} from ${tag} (${commit:0:12})"

sed \
	-e "s|@TAG@|${tag}|g" \
	-e "s|@PKGVER@|${pkgver}|g" \
	-e "s|@PKGREL@|1|g" \
	-e "s|@ARCH@|${arch}|g" \
	-e "s|@COMMIT@|${commit}|g" \
	"$PKGBUILD_TPL" >PKGBUILD

makepkg --syncdeps --noconfirm --noprogressbar --cleanbuild --clean

pkg=$(ls -1 photocraft-*.pkg.tar.zst)
echo ">> built ${pkg}"

install -Dm644 "$pkg" "${REPO_DIR}/${arch}/${pkg}"

# Record what was produced so the matrix job can report it.
{
	echo "tag=${tag}"
	echo "arch=${arch}"
	echo "pkgver=${pkgver}"
	echo "commit=${commit}"
	echo "package=${pkg}"
} >"${REPO_DIR}/${arch}/${pkg}.info"