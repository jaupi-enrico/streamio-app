#!/usr/bin/env bash
# Installs Streamio from this extracted tarball. Self-contained on purpose:
# unlike scripts/install-linux.sh (which builds from a checkout), everything
# this needs is sitting next to it, so a recipient needs no Flutter toolchain
# and no repository — just the archive.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

user_install=false
if [[ "$(id -u)" != "0" ]] && ! command -v sudo >/dev/null 2>&1; then
  # No root and no way to get it — the per-user layout is the only one that
  # can work, so default to it rather than failing on the first mkdir.
  user_install=true
fi

for arg in "$@"; do
  case "$arg" in
    --user) user_install=true ;;
    --system) user_install=false ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--user|--system]

Installs Streamio on this machine.

  --user    Install to ~/.local (no root needed).
  --system  Install to /opt/streamio + /usr/local/bin (needs root/sudo).

With neither flag, a system-wide install is used when root or sudo is
available, and a per-user install otherwise.
EOF
      exit 0
      ;;
    *) die "unknown argument '$arg' (see --help)" ;;
  esac
done

[[ -x ./streamio ]] || die "'streamio' not found next to this script — run it from inside the extracted folder."

if [[ "$user_install" == true ]]; then
  install_dir="$HOME/.local/share/streamio"
  bin_dir="$HOME/.local/bin"
  desktop_dir="$HOME/.local/share/applications"
  sudo=""
else
  install_dir="/opt/streamio"
  bin_dir="/usr/local/bin"
  desktop_dir="/usr/share/applications"
  if [[ "$(id -u)" == "0" ]]; then
    sudo=""
  else
    command -v sudo >/dev/null 2>&1 || die "'sudo' is required for a system-wide install (or pass --user)."
    sudo="sudo"
  fi
fi

echo "Installing to ${BOLD}${install_dir}${RESET}..."
$sudo rm -rf "$install_dir"
$sudo mkdir -p "$install_dir"
# Everything except this installer and its sibling docs — the bundle has to
# stay laid out exactly as it is, since the binary finds lib/ and data/ next
# to itself.
for entry in *; do
  case "$entry" in
    install.sh|uninstall.sh|README.txt) continue ;;
  esac
  $sudo cp -r "$entry" "$install_dir/"
done
$sudo cp uninstall.sh "$install_dir/uninstall.sh"
$sudo chmod +x "$install_dir/uninstall.sh"

echo "Linking ${bin_dir}/streamio..."
mkdir -p "$bin_dir" 2>/dev/null || $sudo mkdir -p "$bin_dir"
$sudo ln -sf "$install_dir/streamio" "$bin_dir/streamio"

echo "Adding launcher entry..."
$sudo mkdir -p "$desktop_dir"
desktop_entry="[Desktop Entry]
Type=Application
Name=Streamio
Comment=Watch your Streamio library
Exec=${install_dir}/streamio
Icon=${install_dir}/streamio.png
Terminal=false
Categories=AudioVideo;Player;
"
if [[ -n "$sudo" ]]; then
  printf '%s' "$desktop_entry" | $sudo tee "$desktop_dir/streamio.desktop" >/dev/null
else
  printf '%s' "$desktop_entry" > "$desktop_dir/streamio.desktop"
fi
command -v update-desktop-database >/dev/null 2>&1 && $sudo update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "${YELLOW}note:${RESET} ${bin_dir} is not on your PATH — use the app-menu entry, or add it." ;;
esac

echo
echo "${GREEN}Installed.${RESET} Launch 'Streamio' from your app menu, or run 'streamio'."
echo "To remove it later: ${install_dir}/uninstall.sh"
