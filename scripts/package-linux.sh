#!/usr/bin/env bash
# Packages the Linux release build into something you can hand to someone who
# doesn't have a Flutter toolchain: a self-installing tarball, and a .deb when
# dpkg-deb is available. Output lands in dist/.
#
# scripts/install-linux.sh installs onto *this* machine from a checkout; this
# script produces artifacts for other machines. scripts/release.sh calls it and
# attaches whatever it produces to the GitHub release.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

skip_build=false
want_deb=auto
out_dir="dist"
for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=true ;;
    --no-deb) want_deb=false ;;
    --deb) want_deb=true ;;
    --out=*) out_dir="${arg#--out=}" ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--skip-build] [--deb|--no-deb] [--out=DIR]

Builds build/linux/x64/release/bundle and packages it as:
  <out>/streamio-<version>-linux-x64.tar.gz   self-installing archive
  <out>/streamio_<version>_amd64.deb          when dpkg-deb is available

  --skip-build  Reuse the existing bundle instead of rebuilding.
  --deb         Fail if dpkg-deb is missing (default: skip the .deb).
  --no-deb      Don't build a .deb at all.
  --out=DIR     Output directory (default: dist).
EOF
      exit 0
      ;;
    *) die "unknown argument '$arg' (see --help)" ;;
  esac
done

version_line="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//')"
[[ -n "$version_line" ]] || die "couldn't find a 'version:' line in pubspec.yaml."
semver="${version_line%%+*}"
build_number="${version_line##*+}"

bundle_dir="build/linux/x64/release/bundle"
if [[ "$skip_build" == false ]]; then
  command -v flutter >/dev/null 2>&1 || die "'flutter' is required but not found in PATH."
  echo "Building Linux release bundle..."
  # See scripts/release.sh for what STREAMIO_PROXY_HOSTS is; empty is fine.
  build_defines=()
  if [[ -n "${STREAMIO_PROXY_HOSTS:-}" ]]; then
    build_defines+=(--dart-define=STREAMIO_PROXY_HOSTS="$STREAMIO_PROXY_HOSTS")
  fi
  flutter build linux --release ${build_defines[@]+"${build_defines[@]}"}
fi
[[ -x "$bundle_dir/streamio" ]] || die "'$bundle_dir/streamio' missing — run without --skip-build."

mkdir -p "$out_dir"
stage_root="$(mktemp -d)"
trap 'rm -rf "$stage_root"' EXIT

# ── tarball ────────────────────────────────────────────────────
pkg_name="streamio-${semver}-linux-x64"
stage="${stage_root}/${pkg_name}"
mkdir -p "$stage"
cp -r "$bundle_dir"/. "$stage/"
cp assets/icon/app-icon.png "$stage/streamio.png"
install -m 755 scripts/packaging/linux/install.sh "$stage/install.sh"
install -m 755 scripts/packaging/linux/uninstall.sh "$stage/uninstall.sh"

cat > "$stage/README.txt" <<EOF
Streamio ${semver} (build ${build_number}) — Linux x86_64

The app is self-contained: the 'streamio' binary, its bundled libraries in
lib/ (including libmpv for playback), and data/. Nothing else to install.

To try it without installing:
    ./streamio

To install it properly (app-menu entry + 'streamio' on your PATH):
    ./install.sh              # system-wide, asks for your sudo password
    ./install.sh --user       # just for you, no password needed

To remove it later:
    ./uninstall.sh

You'll be asked for your Streamio server address the first time you run it.

Requires a 64-bit Linux with GTK 3 (any current desktop distro has it;
Debian/Ubuntu: libgtk-3-0, Fedora: gtk3, Arch: gtk3).
EOF

tarball="${out_dir}/${pkg_name}.tar.gz"
rm -f "$tarball"
tar -czf "$tarball" -C "$stage_root" "$pkg_name"
echo "${GREEN}Wrote${RESET} ${BOLD}${tarball}${RESET} ($(du -h "$tarball" | cut -f1))"

# ── .deb ───────────────────────────────────────────────────────
if [[ "$want_deb" != false ]]; then
  if ! command -v dpkg-deb >/dev/null 2>&1; then
    if [[ "$want_deb" == true ]]; then
      die "'dpkg-deb' not found (Arch: 'pacman -S dpkg', Debian/Ubuntu: 'apt install dpkg')."
    fi
    echo "${YELLOW}Skipping .deb${RESET} — 'dpkg-deb' not found in PATH."
  else
    # Debian versions may not contain '+' followed by anything unusual, and the
    # build number is more useful as a package revision anyway: 1.4.2-15.
    deb_version="${semver}-${build_number}"
    deb_root="${stage_root}/deb"
    mkdir -p "$deb_root/DEBIAN" \
             "$deb_root/opt/streamio" \
             "$deb_root/usr/bin" \
             "$deb_root/usr/share/applications" \
             "$deb_root/usr/share/icons/hicolor/512x512/apps"

    cp -r "$bundle_dir"/. "$deb_root/opt/streamio/"
    cp assets/icon/app-icon.png "$deb_root/opt/streamio/streamio.png"
    cp assets/icon/app-icon.png "$deb_root/usr/share/icons/hicolor/512x512/apps/streamio.png"
    ln -sf /opt/streamio/streamio "$deb_root/usr/bin/streamio"

    cat > "$deb_root/usr/share/applications/streamio.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Streamio
Comment=Watch your Streamio library
Exec=/opt/streamio/streamio
Icon=streamio
Terminal=false
Categories=AudioVideo;Player;
EOF

    # Installed-Size is in KiB and advisory; apt shows it before installing.
    installed_size="$(du -sk "$deb_root" | cut -f1)"
    cat > "$deb_root/DEBIAN/control" <<EOF
Package: streamio
Version: ${deb_version}
Section: video
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libc6
Installed-Size: ${installed_size}
Maintainer: Streamio <noreply@streamio.local>
Description: Streamio client
 Desktop client for a self-hosted Streamio server: browse and search your
 library, watch, and download for offline playback.
 .
 Playback libraries (libmpv and friends) are bundled with the application,
 so nothing beyond GTK 3 is required.
EOF

    # dpkg-deb refuses anything it doesn't own being non-root-writable; the
    # bundle comes out of the build directory with the builder's uid, so
    # normalize ownership metadata rather than requiring fakeroot.
    chmod -R go-w "$deb_root"
    deb_path="${out_dir}/streamio_${deb_version}_amd64.deb"
    rm -f "$deb_path"
    dpkg-deb --root-owner-group --build "$deb_root" "$deb_path" >/dev/null
    echo "${GREEN}Wrote${RESET} ${BOLD}${deb_path}${RESET} ($(du -h "$deb_path" | cut -f1))"
  fi
fi
