#!/usr/bin/env bash
# Removes an install made by the install.sh shipped in the same tarball.
# Works both from the extracted folder and from the installed copy (install.sh
# drops one at <install-dir>/uninstall.sh).
set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; RESET=$'\033[0m'
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

user_install=false
system_only=false
for arg in "$@"; do
  case "$arg" in
    --user) user_install=true; system_only=false ;;
    --system) system_only=true; user_install=false ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--user|--system]

Removes Streamio. With neither flag, whichever install exists is removed
(both, if both exist).
EOF
      exit 0
      ;;
    *) die "unknown argument '$arg' (see --help)" ;;
  esac
done

remove_install() {
  local install_dir="$1" bin_link="$2" desktop_file="$3" sudo="$4"
  [[ -e "$install_dir" || -L "$bin_link" || -e "$desktop_file" ]] || return 1
  echo "Removing ${install_dir}..."
  $sudo rm -rf "$install_dir"
  $sudo rm -f "$bin_link" "$desktop_file"
  return 0
}

sudo_cmd=""
if [[ "$(id -u)" != "0" ]] && command -v sudo >/dev/null 2>&1; then
  sudo_cmd="sudo"
fi

removed=false
if [[ "$user_install" != true ]]; then
  if remove_install "/opt/streamio" "/usr/local/bin/streamio" "/usr/share/applications/streamio.desktop" "$sudo_cmd"; then
    removed=true
  fi
fi
if [[ "$system_only" != true ]]; then
  if remove_install "$HOME/.local/share/streamio" "$HOME/.local/bin/streamio" "$HOME/.local/share/applications/streamio.desktop" ""; then
    removed=true
  fi
fi

[[ "$removed" == true ]] || die "no Streamio install found."
echo "${GREEN}Removed.${RESET} Your account and downloads in ~/.local/share are untouched."
