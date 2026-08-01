# Cutting a new app release

How to ship a new version of the Flutter client, and how to tell the server about it so
existing installs actually find out. Mirrors the server's own version story (`../web/CLAUDE.md`
→ "Versioning and updates"), but the app has no git tag to key off of — `pubspec.yaml` is the
single source of truth, and the server's admin-configured policy is what makes an update visible
to users.

Current setup: builds are shared manually (no Play Store, no app-hosted download server yet), and
the release build signs with the **debug keystore** — a placeholder in
`android/app/build.gradle` (`signingConfig = signingConfigs.getByName("debug")`). Fine for
sideloading to people you know; revisit before this goes any wider (see "Real release signing"
at the bottom).

## 1. Bump the version

Edit `pubspec.yaml`:

```yaml
version: 1.1.0+2
```

This is `<semver>+<build number>`.

- **Semver** (`1.1.0`) — what `AppVersion.current` reports as `X-Client-Version` on every
  request, and what you'll type into the server's "Latest app version" / "Minimum supported"
  fields (step 3). Bump it for anything user-visible: `patch` for a bug fix, `minor` for a new
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

## 3. Get it to people

However you're distributing it today (manual share). Two things depend on where it ends up:

- **The download link** — wherever you put the APK (a chat, a file share, your own server),
  that URL is what you'll paste into "Download URL" in step 4. Without it, the in-app "update
  available" prompt has nowhere to send someone.
- **Enforcement** (optional) — if you ever raise "Minimum supported" and turn enforcement on, the
  server starts rejecting requests from older builds with 426 (`auth/clientVersion.ts`). Doing
  that before the new build is actually reachable locks people out with nowhere to go — only
  raise `minSupported` once the new build is live at `downloadUrl`.

## 4. Tell the server about it

This is the step that actually makes anyone see "update available" — bumping `pubspec.yaml`
alone changes nothing for installed apps, since they only find out by asking the server.

In the account page, **Admin tab → App Version Policy** (`web/public/account.html`,
admin-only — gated by `ADMIN_EMAILS`):

| Field | What to put |
|---|---|
| Latest app version | The semver you just set, e.g. `1.1.0` (no build number) |
| Minimum supported | Leave alone unless you want older builds blocked, not just nudged |
| Download URL | Wherever step 3 put the APK |
| Message | Optional — shown in the update prompt ("what's new") |
| Block outdated apps | Off = suggest only. On = 426s anything below "Minimum supported" |

Same thing via API if you'd rather script it (admin JWT required):

```bash
curl -X PUT https://your-server/api/settings/client-version \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latest": "1.1.0",
    "min_supported": "",
    "download_url": "https://example.com/streamio-1.1.0.apk",
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
- [ ] APK distributed, download link in hand
- [ ] Admin → App Version Policy updated on the server (`latest` at minimum)
- [ ] Only flip "Block outdated apps" on / raise "Minimum supported" once the link above is live

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
