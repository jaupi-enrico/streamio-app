# Cutting a new app release

How to ship a new version of the Flutter client, and how to tell the server about it so
existing installs actually find out. Mirrors the server's own version story (`../../web/CLAUDE.md`
→ "Versioning and updates"), but the app has no git tag to key off of — `pubspec.yaml` is the
single source of truth, and the server's admin-configured policy is what makes an update visible
to users.

Current setup: no Play Store — the server hosts the APK itself (uploaded through the admin UI,
step 4) and the app downloads updates straight from it. The release build signs with the
**debug keystore** — a placeholder in `android/app/build.gradle`
(`signingConfig = signingConfigs.getByName("debug")`). Fine for sideloading to people you know;
revisit before this goes any wider (see "Real release signing" at the bottom).

## The easy way

```bash
./scripts/release.sh
```

Does steps 1–4 below interactively: checks the tree is clean and in sync with `origin`, prompts
for major/minor/patch, a description, and whether this update is **mandatory**, bumps
`pubspec.yaml` (semver **and** build number), runs `flutter pub get`/`analyze`/`test`, builds the
release APK, commits (`Release X.Y.Z+N`) and pushes. After the APK it offers to run
`scripts/package-linux.sh` (step 2b) and scoops up any Windows artifacts already sitting in
`dist/` for this version — desktop packaging never aborts a release, it warns and carries on. If
the commit was pushed, it then — after asking — tags the commit `vX.Y.Z+N`, pushes the tag, and
creates a GitHub release for that tag via `gh release create`, with the APK **and every desktop
package it found** attached as release assets and the description as the release notes (requires
the `gh` CLI, authenticated: `gh auth login`). Finally — after asking — it logs
into a server as an admin, sets `latest` and `notes` on `/api/settings/client-version`, and
uploads the APK to `/api/settings/client-version/apk`.

If you answered "yes" to mandatory, it raises `minSupported` to the new version and turns
`enforce` on with one more `PUT` — but only *after* the APK upload succeeds, so older clients are
never blocked before the download link that fixes them actually works. Answering "no" (the
default) leaves `minSupported`/`enforce` untouched, same as before this prompt existed.

### Server URL and admin credentials

Put them in **`scripts/release.env`** so a release isn't a typing exercise:

```bash
cp scripts/release.env.example scripts/release.env
$EDITOR scripts/release.env
chmod 600 scripts/release.env      # it holds a password
```

```bash
STREAMIO_SERVER_URL="https://streamio.example.com"
STREAMIO_ADMIN_EMAIL="you@example.com"
STREAMIO_ADMIN_PASSWORD="your-password"
#STREAMIO_PROXY_HOSTS=""            # optional; see docs/playback.md#source-proxying
#STREAMIO_ADMIN_TOKEN=""           # optional; if set, the login is skipped entirely
```

The file is sourced by the script, so it's plain shell assignments — quote anything containing
spaces or `#`. It's **gitignored** (`/scripts/release.env`), and the script warns if it ever ends
up tracked or world-readable. Point `STREAMIO_RELEASE_ENV=/path/to/other.env` at a different file
to keep credentials for more than one server.

Everything in it is optional; whatever is missing is prompted for (the password with echo off).
Variables already exported in your environment win over the file, so a one-off
`STREAMIO_SERVER_URL=https://staging.example.com ./scripts/release.sh` still works. The admin
account must be listed in the server's `ADMIN_EMAILS`.

It deliberately sets `latest` **before** uploading the APK — the upload handler stamps
`apkVersion` from whatever `latest` currently is, so doing it in that order is what makes
`apkVersion` land on the build you just shipped instead of the previous one. It never touches
`minSupported`/`enforce` — raise those by hand once the new build is confirmed working (see
step 4).

Everything below is what the script automates, useful if you want to do a step by hand or the
script can't reach your server.

## 1. Bump the version

Edit `pubspec.yaml`:

```yaml
version: 1.1.0+2
```

This is `<semver>+<build number>`.

- **Semver** (`1.1.0`) — what `AppVersion.current` reports as `X-Client-Version` on every
  request, and what you'll type into the server's "Latest app version" / "Minimum supported"
  fields (step 4). Bump it for anything user-visible: `patch` for a bug fix, `minor` for a new
  feature, `major` for a breaking change to how the app talks to the server (matching
  `API_VERSION` bumps on the server side, which are rare).
- **Build number** (`+2`) — must strictly increase on every release, forever, regardless of the
  semver. It's what Android/iOS use to decide "is this actually newer" (a user with `+2`
  installed can't "upgrade" to another build also tagged `+2`). Don't reset it when bumping
  semver; just keep incrementing. Check the last one with:

  ```bash
  git log -p --follow -- pubspec.yaml | grep '^[+-]version:'
  ```

## 2. Build it

```bash
flutter pub get
flutter analyze                       # should be clean
flutter test
flutter build apk --release           # or: flutter build appbundle --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

Sanity-check the version actually baked in before handing it out:

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk AndroidManifest.xml | strings | grep -A1 versionName
```

## 2b. Package the desktop builds (optional)

Android is the only platform with an in-app update channel; Linux and Windows ship as plain
downloads on the GitHub release, so people you hand the app to have something to double-click.

```bash
./scripts/package-linux.sh          # dist/streamio-1.1.0-linux-x64.tar.gz
                                    # dist/streamio_1.1.0-2_amd64.deb   (needs dpkg-deb)
```

The tarball carries the whole relocatable bundle plus a self-contained `install.sh`/`uninstall.sh`
(no Flutter, no repo needed on the receiving end); the `.deb` installs the same thing through
`apt`/`dpkg`. `--skip-build` reuses an existing `build/linux/x64/release/bundle`, `--no-deb` skips
the package, `--out=DIR` moves the output.

**Windows must be built on Windows** — Flutter has no cross-compilation for that target. On a
Windows machine with the Flutter Windows toolchain (Visual Studio + "Desktop development with
C++"):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package-windows.ps1
```

That produces `dist\streamio-1.1.0-windows-x64.zip` (portable — unzip and run `streamio.exe`) and,
if [Inno Setup 6](https://jrsoftware.org/isinfo.php) is installed (`winget install
JRSoftware.InnoSetup`), `dist\streamio-1.1.0-windows-x64-setup.exe` from
`scripts/packaging/windows/streamio.iss`. The installer is per-machine when the user can elevate
and per-user when they can't, adds Start-menu (and optionally desktop) shortcuts, and registers a
normal uninstall entry. Neither artifact is code-signed, so **SmartScreen will show an "unknown
publisher" warning** — that's expected and the bundled README says so.

Copy `dist\` over to the machine that runs `scripts/release.sh` (or upload by hand with
`gh release upload`) and the release script picks up anything there matching the version being
released.

`dist/` is gitignored.

## 3. Tag it and create a GitHub release

```bash
git tag -a "v$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//')" -m "Release ..."
git push origin --tags
gh release create "v1.1.0+2" \
  build/app/outputs/flutter-apk/app-release.apk \
  dist/streamio-1.1.0-linux-x64.tar.gz \
  dist/streamio_1.1.0-2_amd64.deb \
  dist/streamio-1.1.0-windows-x64.zip \
  dist/streamio-1.1.0-windows-x64-setup.exe \
  --title "1.1.0+2" --notes "Fixes sessions getting dropped on app close."
```

The tag includes the build number (`v1.1.0+2`, not just `v1.1.0`) since the build number, not the
semver, is what strictly increases every release — two releases can share a semver. This gives the
release a permanent, downloadable home on GitHub independent of any particular server, and is a
reasonable value to paste into "Download URL" in step 4 below instead of hosting the APK on the
server itself.

## 4. Upload it to the server

In the account page, **Admin tab → App Version Policy** (`web/public/account.html`,
admin-only — gated by `ADMIN_EMAILS`), under "Host the build on this server": pick
`app-release.apk` from step 2 and hit **Upload APK**. (Skip this if you'd rather point
"Download URL" at the GitHub release from step 3 instead — see the next section.)

That does two things:

- stores the file on the server (`GET /api/version/download` — public/unauthenticated, so even a
  build already blocked by "Block outdated apps" below can still reach it and escape),
- fills in the **Download URL** field above with that server's own download link, replacing
  whatever was there before.

The upload only replaces the *file* — it doesn't touch `latest`/`minSupported`/`notes`/
`enforce`, and doesn't save the form by itself. Still need to fill those in and hit **Save**
(next step) for any of it to take effect.

If you'd rather point at an external link (GitHub release, etc.) instead of hosting it here, just
type over the Download URL field by hand after uploading, or skip the upload entirely — it's a
plain editable field either way. Editing it away from the server's own link doesn't delete the
uploaded file, it just stops the server from serving it.

## 5. Set the version policy and save

Same card, the rest of the fields:

| Field | What to put |
|---|---|
| Latest app version | The semver you just set, e.g. `1.1.0` (no build number) |
| Minimum supported | Leave alone unless you want older builds blocked, not just nudged |
| Download URL | Auto-filled by step 4, or paste the GitHub release link from step 3 instead |
| Message | Optional — shown in the update prompt ("what's new") |
| Block outdated apps | Off = suggest only. On = 426s anything below "Minimum supported" |

Then hit **Save**. Raising "Minimum supported" and turning enforcement on rejects every older
build immediately (`auth/clientVersion.ts`) — only do that once the new build is actually
reachable at Download URL, i.e. after step 4's upload has landed (or the GitHub release / other
external link is live).

Same thing via API if you'd rather script the policy fields (the upload itself needs a real
multipart POST, not shown here — admin JWT required either way):

```bash
curl -X PUT https://your-server/api/settings/client-version \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latest": "1.1.0",
    "min_supported": "",
    "notes": "Fixes sessions getting dropped on app close.",
    "enforce": false
  }'
```

Every running app picks this up the next time it calls `/api/version` (once per launch, plus a
listener for a 426 that can arrive on any request — see `updateCheckProvider` /
`clientOutdatedProvider` in `lib/state/update_providers.dart`), no server restart needed.

## Checklist

- [ ] `pubspec.yaml` version bumped (semver **and** build number)
- [ ] `flutter analyze` / `flutter test` clean
- [ ] `flutter build apk --release` built and version-checked
- [ ] Desktop packages built, if this release is going to desktop users (`scripts/package-linux.sh`
      here, `scripts\package-windows.ps1` on a Windows machine, artifacts copied into `dist/`)
- [ ] Commit pushed, tag `vX.Y.Z+N` pushed, GitHub release created with the APK (and any desktop
      packages) attached
- [ ] APK uploaded via Admin → App Version Policy (or the GitHub release link pasted into
      Download URL)
- [ ] `latest` (and `notes`, if any) set and saved
- [ ] Only flip "Block outdated apps" on / raise "Minimum supported" once the build above is live

## Real release signing (later, not blocking)

`android/app/build.gradle` currently points the `release` build type at the debug signing
config — fine for sideloading to people you trust, but every build is signed with the same
publicly-known debug key, which:

- lets anyone repackage a build and have it pass as "the same app" to Android (shared signature),
- would need a full replace-not-upgrade reinstall for every user the day you switch to a real
  key, since Android refuses to install a differently-signed update over an existing one.

When that becomes worth doing: generate a keystore (`keytool -genkey -v -keystore
release.jks ...`), wire it into `android/app/build.gradle` via `key.properties` (standard Flutter
recipe, not covered here), and **keep the keystore + its password somewhere durable and backed
up** — losing it means every future release is that forced reinstall, permanently.
