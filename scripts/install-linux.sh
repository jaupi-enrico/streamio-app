#!/usr/bin/env bash
# Builds the Linux release bundle and installs it on this machine, per the
# manual steps in docs/getting-started.md ("Installing the release build").
# There's no packaging (.desktop/.deb/AppImage) for this project, so this
# just automates the copy-into-place routine: build/linux/x64/release/bundle
# -> a permanent directory, a symlink on PATH, and a .desktop launcher entry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

user_install=false
skip_build=false
for arg in "$@"; do
  case "$arg" in
    --user) user_install=true ;;
    --skip-build) skip_build=true ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--user] [--skip-build]

  --user        Install to ~/.local/{share/streamio,bin,share/applications}
                instead of /opt/streamio, /usr/local/bin, /usr/share/applications.
                No sudo required.
  --skip-build  Reuse the existing build/linux/x64/release/bundle instead of
                running 'flutter build linux --release' again.
EOF
      exit 0
      ;;
    *) die "unknown argument '$arg' (see --help)" ;;
  esac
done

command -v flutter >/dev/null 2>&1 || die "'flutter' is required but not found in PATH."

if [[ "$user_install" == true ]]; then
  install_dir="$HOME/.local/share/streamio"
  bin_dir="$HOME/.local/bin"
  desktop_dir="$HOME/.local/share/applications"
  sudo=""
else
  install_dir="/opt/streamio"
  bin_dir="/usr/local/bin"
  desktop_dir="/usr/share/applications"
  sudo="sudo"
  command -v sudo >/dev/null 2>&1 || die "'sudo' is required for a system-wide install (or pass --user)."
fi

bundle_dir="build/linux/x64/release/bundle"

if [[ "$skip_build" == false ]]; then
  echo "Building release bundle..."
  flutter build linux --release
fi
[[ -d "$bundle_dir" ]] || die "'$bundle_dir' not found — run without --skip-build."
[[ -x "$bundle_dir/streamio" ]] || die "'$bundle_dir/streamio' missing or not executable."

echo "Installing to ${BOLD}${install_dir}${RESET}..."
$sudo mkdir -p "$install_dir"
$sudo cp -r "$bundle_dir"/* "$install_dir/"

echo "Linking ${bin_dir}/streamio..."
mkdir -p "$bin_dir" 2>/dev/null || $sudo mkdir -p "$bin_dir"
$sudo ln -sf "$install_dir/streamio" "$bin_dir/streamio"

echo "Adding launcher entry..."
$sudo cp assets/icon/app-icon.png "$install_dir/streamio.png"
$sudo mkdir -p "$desktop_dir"
desktop_entry="[Desktop Entry]
Type=Application
Name=Streamio
Exec=${install_dir}/streamio
Icon=${install_dir}/streamio.png
Categories=AudioVideo;Player;
"
if [[ -n "$sudo" ]]; then
  printf '%s' "$desktop_entry" | $sudo tee "$desktop_dir/streamio.desktop" >/dev/null
else
  printf '%s' "$desktop_entry" > "$desktop_dir/streamio.desktop"
fi

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "${YELLOW}warning:${RESET} ${bin_dir} is not on your PATH." ;;
esac

echo
echo "${GREEN}Installed.${RESET} Run 'streamio', or launch it from your app menu."
echo "Re-run this script after every release to update the installed copy."
