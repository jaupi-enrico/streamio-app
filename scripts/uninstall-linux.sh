#!/usr/bin/env bash
# Removes what scripts/install-linux.sh put in place: the install directory,
# the PATH symlink, and the .desktop launcher entry. Mirrors its --user flag
# so it targets the same locations.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

user_install=false
for arg in "$@"; do
  case "$arg" in
    --user) user_install=true ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--user]

  --user  Remove the per-user install (~/.local/{share/streamio,bin,share/applications})
          instead of the system-wide one (/opt/streamio, /usr/local/bin, /usr/share/applications).
EOF
      exit 0
      ;;
    *) die "unknown argument '$arg' (see --help)" ;;
  esac
done

if [[ "$user_install" == true ]]; then
  install_dir="$HOME/.local/share/streamio"
  bin_link="$HOME/.local/bin/streamio"
  desktop_file="$HOME/.local/share/applications/streamio.desktop"
  sudo=""
else
  install_dir="/opt/streamio"
  bin_link="/usr/local/bin/streamio"
  desktop_file="/usr/share/applications/streamio.desktop"
  sudo="sudo"
  command -v sudo >/dev/null 2>&1 || die "'sudo' is required for a system-wide uninstall (or pass --user)."
fi

found=false
[[ -e "$install_dir" ]] && found=true
[[ -e "$bin_link" || -L "$bin_link" ]] && found=true
[[ -e "$desktop_file" ]] && found=true

if [[ "$found" == false ]]; then
  echo "Nothing found at ${install_dir}, ${bin_link}, or ${desktop_file} — already uninstalled."
  exit 0
fi

echo "This will remove:"
[[ -e "$install_dir" ]] && echo "  ${install_dir}"
[[ -e "$bin_link" || -L "$bin_link" ]] && echo "  ${bin_link}"
[[ -e "$desktop_file" ]] && echo "  ${desktop_file}"
read -r -p "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || die "aborted."

if [[ -e "$install_dir" ]]; then
  $sudo rm -rf "$install_dir"
  echo "Removed ${install_dir}."
fi
if [[ -e "$bin_link" || -L "$bin_link" ]]; then
  $sudo rm -f "$bin_link"
  echo "Removed ${bin_link}."
fi
if [[ -e "$desktop_file" ]]; then
  $sudo rm -f "$desktop_file"
  echo "Removed ${desktop_file}."
fi

echo
echo "${GREEN}Uninstalled.${RESET}"
