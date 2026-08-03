#!/usr/bin/env bash
# Interactive release cutter for the Flutter client: bumps pubspec.yaml's
# version, builds the release APK, commits/pushes, then uploads the build
# straight to a Streamio server and updates its client-version policy — the
# steps documented by hand in docs/releasing.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

for bin in flutter jq curl git; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required but not found in PATH."
done

# ── Credentials ────────────────────────────────────────────────
# scripts/release.env holds the server URL and admin login so a release doesn't
# have to be typed out every time. It is gitignored (it contains a password);
# see docs/releasing.md and scripts/release.env.example. Anything already
# exported in the environment wins over the file, so a one-off
# `STREAMIO_SERVER_URL=... ./scripts/release.sh` still works.
env_file="${STREAMIO_RELEASE_ENV:-scripts/release.env}"
if [[ -f "$env_file" ]]; then
  pre_url="${STREAMIO_SERVER_URL:-}"
  pre_email="${STREAMIO_ADMIN_EMAIL:-}"
  pre_password="${STREAMIO_ADMIN_PASSWORD:-}"
  pre_token="${STREAMIO_ADMIN_TOKEN:-}"

  set -a
  # shellcheck disable=SC1090
  source "$env_file" || die "couldn't read ${env_file}."
  set +a

  [[ -n "$pre_url" ]] && STREAMIO_SERVER_URL="$pre_url"
  [[ -n "$pre_email" ]] && STREAMIO_ADMIN_EMAIL="$pre_email"
  [[ -n "$pre_password" ]] && STREAMIO_ADMIN_PASSWORD="$pre_password"
  [[ -n "$pre_token" ]] && STREAMIO_ADMIN_TOKEN="$pre_token"

  echo "Loaded release credentials from ${env_file}."
  env_mode="$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%Lp' "$env_file" 2>/dev/null || echo "")"
  if [[ -n "$env_mode" && "${env_mode: -2}" != "00" ]]; then
    echo "${YELLOW}warning:${RESET} ${env_file} is mode ${env_mode} — group/other can read it; 'chmod 600 ${env_file}'."
  fi
  if git ls-files --error-unmatch "$env_file" >/dev/null 2>&1; then
    echo "${YELLOW}warning:${RESET} ${env_file} is tracked by git — it holds a password; untrack it."
  fi
fi

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash your changes first."

branch="$(git branch --show-current)"
if [[ "$branch" != "main" && "$branch" != "master" ]]; then
  echo "${YELLOW}warning:${RESET} you are on '${branch}', not 'main'/'master'."
  read -r -p "Continue anyway? [y/N] " confirm_branch
  [[ "$confirm_branch" =~ ^[Yy]$ ]] || die "aborted."
fi

echo "Fetching latest from origin..."
git fetch origin --quiet
local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse "origin/$branch" 2>/dev/null || echo "")"
[[ "$local_head" == "$remote_head" ]] || die "local '$branch' is not in sync with 'origin/$branch' — pull/push first."

# ── Version bump ───────────────────────────────────────────────
current_version="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//')"
[[ -n "$current_version" ]] || die "couldn't find a 'version:' line in pubspec.yaml."
current_semver="${current_version%%+*}"
current_build="${current_version##*+}"
[[ "$current_build" =~ ^[0-9]+$ ]] || die "pubspec.yaml version '${current_version}' has no numeric build suffix (expected X.Y.Z+N)."

echo "Current version: ${BOLD}${current_version}${RESET}"
echo
echo "What kind of release is this?"
IFS='.' read -r major minor patch <<< "$current_semver"
select bump in "major" "minor" "patch (fix)"; do
  case "$REPLY" in
    1) major=$((major + 1)); minor=0; patch=0; break ;;
    2) minor=$((minor + 1)); patch=0; break ;;
    3) patch=$((patch + 1)); break ;;
    *) echo "Pick 1, 2, or 3." ;;
  esac
done
new_semver="${major}.${minor}.${patch}"
new_build=$((current_build + 1))
new_version="${new_semver}+${new_build}"

echo
echo "Enter a description of this release (used as the commit message and the"
echo "server's client-version 'notes' / update prompt). Finish with an empty line:"
notes=""
while IFS= read -r line; do
  [[ -z "$line" ]] && break
  notes+="${line}"$'\n'
done
notes="$(printf '%s' "$notes" | sed -e '$a\')"
[[ -n "$(printf '%s' "$notes" | tr -d '[:space:]')" ]] || die "a description is required."

echo
read -r -p "Is this a mandatory update — block installs older than ${new_semver}? [y/N] " confirm_mandatory
mandatory=false
[[ "$confirm_mandatory" =~ ^[Yy]$ ]] && mandatory=true

echo
echo "${BOLD}About to release:${RESET}"
echo "  ${current_version} -> ${new_version}"
echo "  branch: ${branch}"
if [[ "$mandatory" == true ]]; then
  echo "  mandatory: ${YELLOW}yes — older builds will be blocked once uploaded${RESET}"
else
  echo "  mandatory: no — suggested only"
fi
echo "  notes:"
printf '%s\n' "$notes" | sed 's/^/    /'
read -r -p "Bump version and build the APK? [y/N] " confirm_build
[[ "$confirm_build" =~ ^[Yy]$ ]] || die "aborted."

sed -i "s/^version:.*/version: ${new_version}/" pubspec.yaml

# ── Build ─────────────────────────────────────────────────────
flutter pub get
flutter analyze
flutter test
flutter build apk --release

apk_path="build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$apk_path" ]] || die "build finished but ${apk_path} is missing."

baked_version="$(unzip -p "$apk_path" AndroidManifest.xml 2>/dev/null | strings | grep -A1 versionName | tail -1 | tr -dc '0-9.' || true)"
echo "APK built. versionName baked in: ${baked_version:-<unknown - binary manifest did not match, harmless>}"

# ── Commit & push ─────────────────────────────────────────────
git add pubspec.yaml
git commit -m "Release ${new_version}" -m "$notes"

echo
read -r -p "Push commit to origin/${branch}? [y/N] " confirm_push
if [[ "$confirm_push" =~ ^[Yy]$ ]]; then
  git push origin "$branch"
else
  echo "${YELLOW}Skipped push.${RESET} Commit is local only — run 'git push' when ready."
fi

# ── Upload to server ────────────────────────────────────────────
echo
read -r -p "Upload the APK to a Streamio server now? [y/N] " confirm_upload
if [[ ! "$confirm_upload" =~ ^[Yy]$ ]]; then
  echo "Skipping upload. APK is at ${apk_path}."
  if [[ "$mandatory" == true ]]; then
    echo "${YELLOW}Note:${RESET} you said this was mandatory, but nothing was uploaded or"
    echo "enforced on the server — that step only happens as part of the upload flow."
  fi
  echo "${GREEN}Done.${RESET} Version ${new_version} built and committed."
  exit 0
fi

server="${STREAMIO_SERVER_URL:-}"
if [[ -z "$server" ]]; then
  read -r -p "Server URL (e.g. https://streamio.example.com): " server
fi
server="${server%/}"
[[ -n "$server" ]] || die "no server URL given."

# -L follows redirects (some deployments front the app with a plain HTTP
# redirect rather than a reverse proxy — e.g. web/redirect/index.ts, which
# 302s every unrecognized path to the current tunnel URL, typically on a
# different host). The --post3xx flags stop curl from downgrading our
# POST/PUT to a GET on that redirect, which is curl's default,
# browser-compatible behavior. --location-trusted keeps the Authorization
# header across that cross-host hop — curl drops it by default for safety,
# but here the redirect target is this same deployment's own tunnel.
CURL=(curl -sS -L --post301 --post302 --post303 --location-trusted)

# Require JSON back so a redirect/proxy that swallowed our request (returning
# an HTML page instead of reaching the API) fails loudly instead of feeding
# garbage to jq.
require_json() {
  jq -e . >/dev/null 2>&1 <<<"$1" || die "$2 — response wasn't JSON, got: $(head -c 200 <<<"$1")"
}

echo "Checking server..."
health_resp="$("${CURL[@]}" -f "${server}/health")" || die "couldn't reach ${server}/health."
require_json "$health_resp" "health check failed"

token="${STREAMIO_ADMIN_TOKEN:-}"
if [[ -z "$token" ]]; then
  email="${STREAMIO_ADMIN_EMAIL:-}"
  [[ -n "$email" ]] || read -r -p "Admin email: " email
  password="${STREAMIO_ADMIN_PASSWORD:-}"
  if [[ -z "$password" ]]; then
    read -r -s -p "Admin password: " password
    echo
  fi

  # X-Client-Version matters here: /api/auth/login is not exempt from the
  # client-version gate (auth/clientVersion.ts), and a request with no
  # version header at all is treated as older than any configured floor.
  login_resp="$("${CURL[@]}" -X POST "${server}/api/auth/login" \
    -H "Content-Type: application/json" -H "X-Client: app" -H "X-Client-Version: ${new_semver}" \
    -d "$(jq -n --arg e "$email" --arg p "$password" '{email:$e,password:$p}')")"
  require_json "$login_resp" "login request failed"
  token="$(jq -r '.access_token // empty' <<<"$login_resp")"
  [[ -n "$token" ]] || die "login failed: $(jq -r '.error // "unknown error"' <<<"$login_resp")"
fi

echo "Setting client-version policy (latest=${new_semver})..."
policy_resp="$("${CURL[@]}" -w '\n%{http_code}' -X PUT "${server}/api/settings/client-version" \
  -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
  -d "$(jq -n --arg l "$new_semver" --arg n "$notes" '{latest: $l, notes: $n}')")"
policy_code="$(tail -1 <<<"$policy_resp")"
policy_body="$(sed '$d' <<<"$policy_resp")"
[[ "$policy_code" == "200" ]] || die "failed to set client-version policy (HTTP ${policy_code}): ${policy_body}"

echo "Uploading APK (this can take a while)..."
upload_resp="$("${CURL[@]}" -w '\n%{http_code}' -X POST "${server}/api/settings/client-version/apk" \
  -H "Authorization: Bearer ${token}" \
  -F "apk=@${apk_path};type=application/vnd.android.package-archive")"
upload_code="$(tail -1 <<<"$upload_resp")"
upload_body="$(sed '$d' <<<"$upload_resp")"
[[ "$upload_code" == "200" ]] || die "APK upload failed (HTTP ${upload_code}): ${upload_body}"

# Only raise the floor once the build above is actually reachable — the APK
# upload just landed and set Download URL, so it's safe now. Doing this
# before the upload would 426 every older client against a download link
# that didn't exist yet.
if [[ "$mandatory" == true ]]; then
  echo "Blocking installs older than ${new_semver}..."
  enforce_resp="$("${CURL[@]}" -w '\n%{http_code}' -X PUT "${server}/api/settings/client-version" \
    -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
    -d "$(jq -n --arg m "$new_semver" '{min_supported: $m, enforce: true}')")"
  enforce_code="$(tail -1 <<<"$enforce_resp")"
  enforce_body="$(sed '$d' <<<"$enforce_resp")"
  [[ "$enforce_code" == "200" ]] || die "failed to enforce minimum version (HTTP ${enforce_code}): ${enforce_body}"
fi

echo
echo "${GREEN}Released ${new_version} and uploaded to ${server}.${RESET}"
if [[ "$mandatory" == true ]]; then
  echo "Marked mandatory: builds older than ${new_semver} are now blocked."
else
  echo "Minimum supported version and enforcement were left untouched — raise those"
  echo "separately (Admin -> App Version Policy) once the build is confirmed working."
fi
