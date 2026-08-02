# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
directory (`app/` — the Flutter client).

## Project

A Flutter client for a self-hosted Streamio server (`../web`). It covers the same ground as the web
frontend — home, catalog, search, providers, details, playback, account, social, watch parties,
admin — and adds offline downloads. `../web/CLAUDE.md` documents the backend it talks to; read that
before changing anything that crosses the wire.

`app/` is **not** part of the backend's git repository (the repo root is `web/`), so changes here
are untracked from git's point of view.

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after changing the drift schema
flutter analyze                       # expected to be clean
flutter test
flutter test test/hls_parser_test.dart                     # one file
flutter test test/api_client_test.dart --plain-name 'redirect'   # one group/test
flutter run
flutter build apk --debug             # catches native/plugin breakage analyze can't
dart run flutter_launcher_icons       # after changing assets/icon/
```

Drift is the **only** code generator — nothing uses freezed, json_serializable or
riverpod_generator, so don't reintroduce annotations expecting them to work.

`flutter analyze` cleanliness is a maintained property. `flutter build apk --debug` is worth running
after dependency or platform-config changes — it catches plugin and manifest breakage the analyzer
cannot see.

Cutting a release (bump `pubspec.yaml`, build the release APK, upload it to a server and set its
client-version policy) is `./scripts/release.sh` — interactive, asks for major/minor/patch and a
description, and confirms before pushing the commit or uploading anything. The server URL and admin
login come from `scripts/release.env` (gitignored; `scripts/release.env.example` is the template),
with the environment overriding it and prompts filling whatever is missing. See `docs/releasing.md`
for the manual steps it wraps and for release-signing caveats.

## Architecture

The app is a thin client: it does **not** scrape. An earlier iteration ported the backend's engine
to Dart; that is gone, and `lib/core/models/` is what survived it.

| Layer | Where |
|---|---|
| HTTP + auth (bearer token, one silent refresh on 401, replay) | `lib/core/api/api_client.dart` |
| One class per backend router | `lib/core/api/{content,auth,account,social,rooms,settings}_api.dart` |
| Wire format → domain models | `lib/core/api/json_mappers.dart` |
| Domain models (mirror `../web/core/models/*.ts`) | `lib/core/models/` |
| Riverpod graph, rooted at the server URL | `lib/state/` |
| Screens | `lib/features/<feature>/` |
| Routing, guards, responsive shell | `lib/routing/` |

**Deserialization is split, deliberately.** The **domain** models (`Movie`, `TvShow`, `Episode`,
`Season`, `Genre`, `People`, `Category`, `PlaybackSource`) mirror `../web/core/models/*.ts`
field-for-field and are parsed by `core/api/json_mappers.dart`, which keeps those classes free of
wire-format concerns — that file is the single place that knows the camelCase shape, the ISO date
strings, and the fact that `/api/shows/:id` has no discriminator (it keys off `seasons`). The
**account/social** types (`AppUser`, `LibraryEntry`, `HistoryEntry`, `Share`, `Room`,
`HostingPoint`, ...) carry their own `fromJson`, because they are snake_case Postgres rows with no
TypeScript counterpart to stay aligned with.

**The provider graph is rooted at the server URL.** There is no compile-time base URL: a Streamio
install is self-hosted and its address changes per deployment, so the user types it in on first run
(`core/config/server_config.dart`, `features/setup/`) and it is stored in `shared_preferences`.
`apiClientProvider` watches it, so changing the server disposes the client and every content/account
provider with it and the app repoints without a restart. Anything reading `apiClientProvider` before
a server is set throws `ServerNotConfigured`; the router's redirect keeps that unreachable.

**Every screen requires an account.** `routing/app_router.dart` inverts the usual guard: only
`/login`, `/register`, `/reset-password`, `/verify-email` and `/server` are reachable signed out,
and everything else — browsing, details, playback, downloads — redirects to `/login` with a
`redirect=` back to where you were. This is why `AuthNotifier.isBootstrapped` exists: the guard has
to tell "still restoring the stored session" (hold on the splash) from "signed out" (go to
`/login`), and it can't use `isLoading` for that, because signing in passes through `loading` too.
It's also why a failed `/api/account/me` falls back to the profile cached in the keystore — an
offline launch must not lock the user out of their downloads.

The address is validated with `GET {base}/health`. If the pasted address is a page URL rather than
the base (`.../streamio/watch`, copied out of a browser mid-browse), the probe walks the path back
one segment at a time and saves whichever base actually answered.

## Cross-cutting invariants

These span both projects; changing one side alone breaks things in ways local tests won't catch.
The backend half of each is described in `../web/CLAUDE.md`.

- **Native auth.** The web frontend keeps its refresh token in an httpOnly cookie, which a native
  client cannot use. Tokens live in the platform keystore (`flutter_secure_storage`). The app sends
  `X-Client: app`, and `sendTokens` in `../web/routes/auth.router.ts` then also returns the refresh
  token in the JSON body and accepts it back in the body on `/refresh` and `/logout`. OAuth works
  the same way via an allowlisted `redirect_uri=streamio://auth`. Browser behavior must stay
  byte-identical when touching this.
- **Only a rejected refresh token ends a session.** `_doRefresh` reports `refreshed`/`transient`/
  `dead`, and only `dead` — a 401/403 from `/api/auth/refresh` itself, or no refresh token at all —
  clears the keystore and fires `onAuthLost`. A 429 from the backend's refresh limiter, a 5xx, a
  redirect, an offline moment: `transient`, the call fails, the session stays. The refresh POST
  follows redirects by hand like every other call. Server side, rotation keeps a 60s grace window
  so a rotation whose response never arrived doesn't strand the client. The room socket can't retry
  a rejected handshake, so it calls `renewAccessToken()` once per reconnect sequence instead.
- **Redirects.** `dart:io` auto-follows redirects for GET/HEAD **only**, so every write would
  otherwise surface a raw 302 — and the `redirect/` tunnel in front of an install redirects by
  design. `api_client.dart` follows them by hand for all methods, preserving method and body
  (unlike a browser, which would downgrade a 302'd POST to GET), and drops the bearer token on an
  https→http downgrade.
- **Path-prefixed installs.** An install mounted at `https://host/streamio` is supported: every URL
  is built by appending to the stored base, so requests land on `.../streamio/api/…`,
  `.../streamio/health` and `wss://.../streamio/ws/rooms/…`. Two consequences — never build a URL
  with `Uri.replace(query: '')` (it emits a trailing `?#` that then prefixes every path), and on the
  server side the reverse proxy must strip the prefix (the backend registers routes at the root)
  while `APP_URL` must *include* it, since `content.router.ts` derives `CAST_PUBLIC_BASE` from it
  and the Chromecast receiver has no page origin to resolve against. Get that wrong and the master
  manifest loads while every segment 404s.
- **vixcloud must be proxied.** Fetched directly, its CDN sees whatever Referer/Origin the client
  sends and intermittently 403s depending on the edge node. The app
  (`features/watch/watch_providers.dart`, and the download manager's 403 fallback) routes it through
  `{base}/api/cast-proxy?direct=1&url=` — a port of `needsSourceProxy()` in
  `../web/public/scripts/watch.js` — which refetches server-side with a fixed Referer/UA and
  rewrites every nested manifest URI.
- **Resolved streams are never cached.** `POST /api/episodes/:id/video` returns signed URLs that
  expire in minutes. Re-resolve per playback attempt; a paused download must re-resolve before
  resuming, because its stored segment URLs are dead.

## Playback

`media_kit` (libmpv) rather than `video_player`: it forwards custom HTTP headers to every child
request of an HLS playlist, which these CDNs require, and it handles demuxed audio/video.

Watch parties connect to `wss://…/ws/rooms/:code?token=…` (`lib/core/api/room_socket.dart`) with the
same reconnect and echo-guard behavior as the web frontend's `room-sync.js`.

Chromecast (`lib/core/cast/cast_service.dart`) resolves its receiver app id rather than hardcoding
one: a device-local override (Account → Chromecast, `core/config/cast_receiver_config.dart`) beats
`castReceiverAppId` from `GET /api/cast-config`, which beats Google's default media receiver. The
override exists because a receiver is registered against a Google Cast console account, not against
a Streamio install, so the person running the app is not necessarily the person who can change
`CAST_RECEIVER_APP_ID` on the server. **The platform SDK reads the id once per process**, so a
changed id needs an app restart — the settings screen says so when it detects that.

Two Cast requirements live outside Dart and fail silently when missing:
`OPTIONS_PROVIDER_CLASS_NAME` (plus `MediaNotificationService`) in `AndroidManifest.xml`, without
which `CastContext.getSharedInstance()` throws and the button never appears; and
`NSLocalNetworkUsageDescription` + `NSBonjourServices` in `Info.plist`, without which iOS 14+
discovers nothing. The Bonjour list names receiver ids literally, so a custom id other than the two
listed there needs adding for iOS discovery to see it. The Cast button hides itself when the
platform doesn't support Cast or the SDK failed to start; a server that can't answer
`/api/cast-config` no longer disables it.

## Offline downloads (`lib/core/download/`)

A download is playable with no network and is not a file the rest of the device can use.

- **Fetching** (`download_manager.dart`) — resolve the stream, parse the master playlist, take the
  video variant plus its demuxed audio rendition, and pull every segment with a bounded worker pool
  and retries. Each segment is a database row, so an interrupted download resumes segment-by-segment
  instead of restarting. Segment URLs are signed and short-lived, so a resume re-resolves the stream
  and re-points the pending rows at fresh URLs. A 403 from the CDN falls back to the server's
  `/api/cast-proxy`, the same workaround the web player uses.
- **Storage** (`segment_store.dart`) — segments land in the app-private support directory, AES-CTR
  encrypted under a 256-bit key generated on first use and kept in the platform keystore. **CTR
  specifically because it is seekable** — a byte offset maps to a counter block. Upstream HLS
  AES-128 is undone at download time so an expiring CDN key can't lock the user out later.
- **Playback** (`local_media_server.dart`) — an HTTP server on `127.0.0.1` (ephemeral port, random
  per-launch path token, running only during playback) synthesizes a master playlist, one media
  playlist per track, and range-aware segment bodies, decrypting on the fly.

The files are invisible to other apps, the gallery and file managers, and a segment copied off the
device is unplayable without the keystore key. It is not DRM against the device's owner and isn't
presented as such.

**Known limitation:** downloads run in-process — leaving or force-quitting the app pauses them; no
foreground service is wired up. Progress recorded while watching offline is stored locally and
pushed to `POST /api/account/history` when the server is next reachable (`offline_sync.dart`).

State: `lib/state/download_providers.dart`; schema in `lib/core/db/app_database.dart`.

## Testing

`test/` covers the places where a wrong answer is silent rather than loud: HLS parsing (demuxed
audio, AES-128, URI resolution), the encrypt → ranged-decrypt round trip offline seeking depends on,
and the API client's contracts (401-refresh-replay, concurrent 401s sharing one refresh since
refresh tokens rotate and are single-use, redirect following, path-prefixed bases).

## Branding

The launcher icon is the website's own mark, copied from `../web/public/icons/site-icon.png` to
`assets/icon/site-icon.png`, with two derived variants: `app-icon.png` (mark at 72% on white,
flattened to RGB — iOS rejects an alpha channel) and `app-icon-foreground.png` (mark at 74% on
transparent, for Android's adaptive icon; `flutter_launcher_icons` adds a 16% inset). Re-run
`dart run flutter_launcher_icons` after changing the art. In-app, `lib/shared/widgets/app_logo.dart`
draws the same mark through a `srcIn` tint — the source art is black and would be invisible on the
dark theme, which only works because the mark is monochrome.
