# Streamio — Flutter client

A Flutter client for a self-hosted Streamio server (`../web`). It covers the same ground as the
web frontend — home, catalog, search, providers, details, playback, account, social, watch
parties, admin — and adds offline downloads.

## Running it

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift database code
flutter run
```

On first launch the app asks for the server address (a DDNS name, the Cloudflare Tunnel URL, or a
LAN address). There is **no compile-time base URL** — a Streamio install is self-hosted and its
address changes per deployment, so the value is typed in and stored in `shared_preferences`
(`lib/core/config/server_config.dart`). It can be changed later from Account → Server.

The address is validated with `GET {base}/health`. If the tunnel is up but still showing its
waiting page, the screen says so and offers to save the address anyway rather than refusing it.

**A path prefix is supported and preserved.** An install mounted behind a reverse proxy at
`https://streamio.ddns.net/streamio` works: every URL the app builds appends to the stored base,
so requests land on `.../streamio/api/…`, `.../streamio/health` and `wss://.../streamio/ws/rooms/…`.
If the address pasted in is a page URL rather than the base (`.../streamio/watch`, copied out of a
browser mid-browse), the probe walks the path back one segment at a time and saves whichever base
actually answered.

Two things on the **server** side have to agree with that prefix when you mount the app under one:

* the reverse proxy must strip the prefix before forwarding, since the backend registers its
  routes at the root (`/api/…`, `/health`, `/ws/rooms/…`);
* `APP_URL` must include the prefix. It's what `content.router.ts` builds `CAST_PUBLIC_BASE` from
  (`${APP_URL}/api/cast-proxy?url=`), and the Chromecast receiver has no page origin to resolve a
  relative URL against — get this wrong and the master manifest loads while every segment 404s.

## Branding

The launcher icon is the website's own mark, copied from
`web/public/icons/site-icon.png` to `assets/icon/site-icon.png`. Two variants are derived from it
(the script lives in this README's history, but they're easy to regenerate by hand):

* `app-icon.png` — the mark at 72% on **white**, flattened to RGB. The source art is black on a
  transparent background, so it needs a backdrop to work as an icon at all; white is how the
  favicon reads on a browser tab. iOS additionally rejects icons with an alpha channel.
* `app-icon-foreground.png` — the mark at 74% on transparent, for Android's adaptive icon.
  `flutter_launcher_icons` wraps the foreground in a 16% inset, so 74% lands at ~50% of the final
  icon — about 76% of the launcher's safe-zone circle, which survives a circular mask.

After changing the art:

```bash
dart run flutter_launcher_icons
```

In-app, the same mark is drawn by `lib/shared/widgets/app_logo.dart` on the setup, sign-in and
wide-layout nav screens. It's tinted through a `srcIn` filter rather than shown as-is — black
artwork would be invisible on this app's dark theme. That trick relies on the mark being
monochrome and would flatten a multi-color logo.

## Architecture

The app is a client of the backend's REST API — it does not scrape anything itself.

| Layer | Where |
|---|---|
| HTTP + auth (bearer token, one silent refresh on 401, replay) | `lib/core/api/api_client.dart` |
| One class per backend router | `lib/core/api/{content,auth,account,social,rooms,settings}_api.dart` |
| Wire format → domain models | `lib/core/api/json_mappers.dart` |
| Domain models (mirror `core/models/*.ts`) | `lib/core/models/` |
| Riverpod graph, rooted at the server URL | `lib/state/` |
| Screens | `lib/features/<feature>/` |
| Routing, guards, shell nav | `lib/routing/` |

Changing the server URL disposes the API client and, transitively, every content and account
provider — the whole app refetches against the new server without a restart.

Tokens live in the platform keystore (`flutter_secure_storage`). The web frontend keeps its
refresh token in an httpOnly cookie, which a native client has no equivalent for, so the app sends
`X-Client: app` and the backend returns the refresh token in the JSON body as well
(`sendTokens` in `web/routes/auth.router.ts`). OAuth uses the same mechanism: the app passes
`redirect_uri=streamio://auth`, and the backend redirects there with both tokens — only for that
one allowlisted target.

## Offline downloads

A downloaded title is playable with no network and is not a file the rest of the device can use.

* **Fetching** (`lib/core/download/download_manager.dart`) — resolve the stream, parse the master
  playlist, take the video variant plus its demuxed audio rendition, and pull every segment with a
  bounded worker pool and retries. Each segment is a database row, so an interrupted download
  resumes segment-by-segment instead of restarting. Segment URLs are signed and short-lived, so a
  resume re-resolves the stream and re-points the pending rows at fresh URLs. A 403 from the CDN
  falls back to the server's `/api/cast-proxy`, the same workaround the web player uses.
* **Storage** (`lib/core/download/segment_store.dart`) — segments are written into the app's
  private support directory, AES-CTR encrypted under a 256-bit key generated on first use and kept
  in the keystore. CTR is chosen because it is seekable: a byte offset maps directly to a counter
  block. Upstream HLS AES-128 is undone at download time, so an expiring upstream key can't lock
  the user out of their own download later.
* **Playback** (`lib/core/download/local_media_server.dart`) — an HTTP server bound to
  `127.0.0.1` on an ephemeral port synthesizes a master playlist, one media playlist per track,
  and range-aware segment bodies, decrypting as it serves. Every path carries a random
  per-launch token so another app on the device can't guess a URL. It runs only during playback.

What this does and doesn't mean: the files are invisible to other apps, the gallery and file
managers, and a segment copied off the device with ADB or root is unplayable without the keystore
key. It is not DRM against the device's owner, and it isn't presented as such.

**Known limitation:** downloads run in the app's own process. Leaving the app for a long time or
force-quitting stops them; they show as *Paused* and resume from the last completed segment. A
foreground service would be needed to keep them running in the background, and isn't wired up.

Progress recorded while watching offline is stored locally and pushed to
`POST /api/account/history` the next time the server is reachable (`lib/core/download/offline_sync.dart`).

## Playback

`media_kit` (libmpv) rather than `video_player`: it forwards custom HTTP headers to every child
request of an HLS playlist, which these CDNs require, and it handles demuxed audio/video. The
player routes a stream through `{base}/api/cast-proxy?direct=1&url=` when the host is
`vixcloud.co` or the URL is plain `http://` — a port of `needsSourceProxy()` in
`web/public/scripts/watch.js`, and for the same reason (the CDN 403s a Referer/Origin it doesn't
expect, and which edge you hit varies by network).

Watch parties connect to `wss://…/ws/rooms/:code?token=…` (`lib/core/api/room_socket.dart`) with
the same reconnect and echo-guard behavior as `room-sync.js`. Chromecast uses the deployment's own
receiver app id from `GET /api/cast-config`, not a hardcoded one; the Cast button hides itself when
the platform or the server doesn't support it.

## Tests

```bash
flutter test
```

Covers the parts where a silent wrong answer would be expensive: HLS parsing (including the
demuxed-audio and AES-128 cases), the encrypt → ranged-decrypt round trip that offline seeking
depends on, and the API client's 401-refresh-replay contract (including that concurrent 401s share
one refresh — refresh tokens rotate and are single-use).

## History

An earlier iteration of this app scraped the source sites directly, in a Dart port of the
backend's engine (`core/core.dart`, `core/providers/`, `core/extractors/`, `core/http/`,
`core/utils/`). That's gone — content comes from the API now, so the port had no callers and
would only have rotted. `core/models/` survived it: those classes mirror the backend's
`core/models/*.ts` field-for-field, which is exactly what the API responses deserialize into.

Removed with it: `dio_cookie_manager`, `cookie_jar` and `html` (session cookies and HTML parsing
were scraping-only concerns) and `jwt_decoder` (never used — the app doesn't inspect token
claims, it just replays a 401). `freezed`, `json_serializable` and `riverpod_generator` went too;
nothing in the tree was annotated for them, so `build_runner` was walking the whole project on
every run to generate nothing. Drift is the only code generator left.
