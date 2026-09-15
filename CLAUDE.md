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

Desktop builds ship as downloads on the GitHub release, not through the in-app updater (which is
Android-only). `scripts/package-linux.sh` turns the Linux bundle into a self-installing tarball and
a `.deb`; `scripts/package-windows.ps1` — **which only runs on Windows**, since Flutter can't
cross-compile that target — produces a portable zip and an Inno Setup installer from
`scripts/packaging/windows/streamio.iss`. Both write to the gitignored `dist/`, and `release.sh`
attaches whatever it finds there for the version being released. `scripts/install-linux.sh` is a
different thing: it installs onto *this* machine from a checkout.

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

**Riverpod 3 wraps what a provider threw.** `ref.watch`/`ref.read` on a provider that failed rethrow
a `ProviderException` (from `package:flutter_riverpod/misc.dart`, not the main entrypoint) holding
the original in `.exception`, so a bare `on ServerNotConfigured` at the call site stops matching
without a compile error. The few providers that legitimately run before /setup — the auth session
and the 426 listener — go through `watchApiClientOrNull`/`readApiClientOrNull`
(`state/api_providers.dart`), and `ErrorState.messageFor` unwraps one level so a screen still shows
the server's own message rather than "Something went wrong". Two other Riverpod 3 behaviours the
state layer depends on: a `Notifier` instance survives a rebuild, so anything per-build (`build()`
resetting `AuthNotifier._bootstrapped`, `GenreBrowseNotifier`'s page counter) has to be reset by
hand, and a write after a rebuild throws — hence the `if (!ref.mounted) return;` guards on async
work started from `build`. Failing providers are also retried automatically; `main.dart` narrows
that to transport failures, since a 400/403 is an answer the server meant and is rendered in place.

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
- **On a TV there is no browser, so OAuth is replaced rather than fixed.** `flutter_web_auth_2`
  hands the consent URL to an Android Custom Tab, which needs a browser package to resolve
  against; an Android TV usually has none, so the launch throws `ActivityNotFoundException` →
  `PlatformException(NO_BROWSER)` and "Continue with Google" looks like a dead button. The answer
  is the pairing flow in `features/auth/tv_login_screen.dart`: `POST /api/auth/device/start` for a
  short code, show it (plus a QR of the same URL with `?code=` filled in), poll
  `/api/auth/device/token` every `interval` until the user approves it from a phone at `{base}/tv`,
  where Google sign-in works normally. `login_screen.dart` routes there two ways — proactively when
  `isTv(context)`, since offering a button that can only throw is worse than not offering it, and
  reactively on a caught `NO_BROWSER` from any device. **The poll answers 200 whether it is waiting
  or done**, so `pollDeviceLogin` distinguishes on `status` and treats a 410 as the code expiring
  (offer a new one) rather than a failure; a poll that fails at the transport is *ignored*, because
  the code is good for ten minutes and one lost request says nothing. The `device_code` is the
  secret and must never be rendered — only the `user_code` goes on screen. See
  `../web/auth/deviceLogin.ts` for the server half and `test/device_login_test.dart` for the
  contract.
- **Only a rejected refresh token ends a session.** `_doRefresh` reports `refreshed`/`transient`/
  `dead`, and only `dead` — a 401/403 from `/api/auth/refresh` itself, or no refresh token at all —
  clears the keystore and fires `onAuthLost`. A 429 from the backend's refresh limiter, a 5xx, a
  redirect, an offline moment: `transient`, the call fails, the session stays. The refresh POST
  follows redirects by hand like every other call. Server side, rotation keeps a 60s grace window
  so a rotation whose response never arrived doesn't strand the client. The room socket can't retry
  a rejected handshake, so it calls `renewAccessToken()` once per reconnect sequence instead.
- **Content requests are personalised, so they must carry the token.** The content and provider
  routers are unauthenticated in the sense that they answer logged out — but they are mounted under
  `optionalAuth`, and the backend resolves both 18+ gates (`AdultService`, from the `adult_content*`
  preferences) off `req.user`. Sent without a bearer token, `/api/providers` and every listing come
  back **200 and gated shut**: the adult-only sources simply aren't in the catalogue and 18+ titles
  aren't in the results, which is indistinguishable from the preferences not being set. `ContentApi`
  therefore passes `optionalAuth: true` on every call — a third mode in `api_client.dart`, the
  counterpart to `fetchPublic`/`ensureSessionQuietly` in `../web/public/scripts/auth.js`: attach the
  token when there is one, refresh it silently when it has aged out, and go through anonymously
  (rather than throw or sign the user out) when there is no session. **Freshness is checked before
  the request, from the JWT's own `exp`** (`TokenStore.hasFreshAccessToken`), because `optionalAuth`
  catches the verification failure and serves the request as a guest — an expired token never 401s
  here, so the usual refresh-and-replay has nothing to react to.
- **Redirects.** `dart:io` auto-follows redirects for GET/HEAD **only**, so every write would
  otherwise surface a raw 302 — and the front end an install is reached through commonly redirects
  by design. `api_client.dart` follows them by hand for all methods, preserving method and body
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
- **Some sources must be proxied.** Fetched directly, their CDNs see whatever Referer/Origin the
  client sends and intermittently 403 depending on the edge node. The app
  (`features/watch/watch_providers.dart`, and the download manager's 403 fallback) routes it through
  `{base}/api/cast-proxy?direct=1&url=` — a port of `needsSourceProxy()` in
  `../web/public/scripts/watch.js` — which refetches server-side with a fixed Referer/UA and
  rewrites every nested manifest URI. **The resolver's own headers are the trigger**, alongside a
  plain `http://` URL: a stream that arrives with headers does so because the CDN demands a
  `Referer`/`Origin` no client can set on its own request, which is the only thing that covers a
  source whose CDN hostnames are generated fresh per resolve, so no host list can match them. Those
  two rules are the whole decision by default — deliberately identical to `watch.js`, which has no
  host list either. **There is no host list in this repository**: a deployment that needs one (a CDN
  that 403s a direct fetch though the resolve asked for no header) passes it at build time as
  `--dart-define=STREAMIO_PROXY_HOSTS=`, comma-separated and suffix-matched, which
  `scripts/release.sh` and the packaging scripts forward from the environment. And
  that `Referer` has to be **forwarded as `ref=`** — the proxy's default is the media host's own
  origin, which some edges 403 outright — for cast URLs and subtitle URLs as much as for local
  playback, since the server threads it into the prefix it rewrites child URIs with. Dropping it is
  what made a title cast fine from a browser and die with a media error from the app.
  `refererOf`/`proxiedSourceUrl` (`features/watch/watch_providers.dart`) and
  `CastService.castProxyBase` are the two places that build it; `test/cast_proxy_url_test.dart` pins
  the shape.
- **Resolved streams are never cached.** `POST /api/episodes/:id/video` returns signed URLs that
  expire in minutes. Re-resolve per playback attempt; a paused download must re-resolve before
  resuming, because its stored segment URLs are dead.
- **The server names its own sources.** `GET /api/providers` returns `catalog` — `name`,
  `displayName`, `description`, `adult` per source — plus `default`, and the app renders exactly
  that (`core/models/provider_info.dart`, `state/core_providers.dart`). There is deliberately no
  table of provider names in this project: one would silently mislabel anything added or renamed in
  `../web/core/core.ts` until the next release. An install predating `catalog` sends bare names, so
  `ProviderInfo.fallback` title-cases them — that path is for old servers, not a place to special-case
  a name. The active provider may legitimately be the empty string (before the catalog loads);
  `_providerQuery` omits it and the server answers from its own default.
- **`catalog` is one entry per *language*, and grouping it is the client's job.** A site offered in
  several languages (it/en, or a dozen regional feeds) is one provider class instantiated per
  language server-side, and each variant is its own `catalog` entry with its own slug — the list
  stays flat so a client written before families existed still shows every variant. The extra fields
  are additive: `family` (shared id), `language` (this variant's code) and `languages` (the family's
  full list, `{code,label,slug}`). `groupProviderFamilies` (`core/models/provider_info.dart`) folds
  them into `ProviderCatalog.families`, which is what both pickers render — one row per site plus a
  language selector. **Both** pickers have to offer the language, not just the Providers screen: the
  home/catalog/search bar (`shared/widgets/provider_picker.dart`) is how most of the app switches
  source, and a grouped entry that could only select the family default made every other language
  unreachable from those screens. That bar is **one button plus a `MenuAnchor` menu, not a chip per
  source** — a chip row left every source past the third off-screen behind a horizontal scroll on a
  phone, and a dozen D-pad presses away on a TV — with the active item `autofocus`ed so a remote can
  enter the overlay at all; the *selected* source's languages stay in the bar as chips, one tap
  each. Two rules that path depends on: the **slug, never the family id, is the wire identity** (it
  is what `?provider=` carries, what keys the response cache, and what is stored in every
  watchlist/history/room row), and the offered languages are built from the catalog entries
  themselves rather than from an entry's `languages` array — the array is consulted only for labels,
  so a variant the server withheld behind an 18+ gate can't be made selectable by it. A server that
  sends none of the three fields yields one single-language family per entry, i.e. exactly the
  ungrouped list. Covered by `test/provider_catalog_test.dart`.
- **`show.providerName` is not a routing key.** It is whatever the provider calls itself
  (`Provider.getName()`), which a current server keeps equal to the registry slug but an older one
  does not: those installs label items with the site's own display name rather than its slug, and
  label a language mirror's items with the name of the provider it was mirrored from. Sent back as
  `?provider=`, a current server answers **400** and an older one silently served the default
  provider's catalogue under the asked-for name — which is why whole catalogues of channels opened
  on "This title could not be found" rather than on an error. Navigation therefore always uses the
  provider the listing was fetched with (`activeProviderNameProvider`, or `widget.provider` on the
  details screen), never the field. The field is fine to *display*; nothing in the app does.
- **Genres are two endpoints, and mixing them fails silently.** `GET /api/genres` is the
  *catalogue* — `{id, name}` per genre, **no shows**; `GET /api/genres/:id` is the *browse*, one
  page of titles on the returned genre's `shows`. Both deserialize through `genreFromJson`, so a
  catalogue entry read as a browse parses cleanly and renders an empty grid — indistinguishable
  from a genre that really is empty. `genresProvider` feeds the filter chips only;
  `genreBrowseProvider` (`features/catalog/catalog_providers.dart`) does the browse and the paging.
  Genre ids are the upstream site's own, so one is meaningless against a different provider — the
  browse is keyed on the active provider and reset when it changes. The route answers **400** when
  the provider has no genre filter and **403** for an 18+ genre behind a closed gate; both are
  shown in place so the filter row stays usable.
- **Account listings page by `X-Page-Rows`, never by the array length.** `/api/account/watchlist`,
  `/favorites`, `/history` and their `/search` variants stayed **bare JSON arrays** when they gained
  paging — the numbers ride in response headers, so a client written before paging is unaffected
  (`core/api/paged_response.dart`). The 18+ gate filters rows *after* the SQL `LIMIT`, so a page of
  24 can arrive as 21: stepping the offset by 21 re-requests the three that were dropped and serves
  the survivors twice, and reads a full page as the last one. `X-Total-Count` is counted before the
  same filter, so it can read high — display it, never page by it. **An absent `X-Page-Rows` means
  the install predates paging and ignored `limit`/`offset` entirely**, answering with the whole
  listing; treat that array as complete and stop, or the app pages forever through the same rows
  (`PagedResponse.paged`). History additionally refetches the old way there, since that endpoint
  *did* honour `limit` before paging and would otherwise show fewer rows than the previous release.
  All of it lives in `PagedListNotifier` (`features/account/account_providers.dart`) and nowhere
  else; `test/account_paging_test.dart` and `test/paged_response_test.dart` pin it.
- **Nothing inside a `NestedScrollView` body gets its own `ScrollController`.** The account tabs are
  the body of one, and its coordinator drives the collapsing hero/tab-bar header through the
  `PrimaryScrollController` it installs — handing a body `ListView` a controller of its own opts it
  out of that coupling and the header silently stops collapsing on that tab alone. So the
  catalog/search infinite-scroll pattern can't be copied literally: paging there uses a
  controller-free `NotificationListener` on `metrics.extentAfter`
  (`features/account/widgets/paging.dart`), and pairs it with a `ScrollMetricsNotification` listener
  for the page that lands too short to fill the viewport and so never emits a scroll at all — the
  stall `fillViewport()` works around in `../web/public/scripts/account.js`.

## Playback

`media_kit` (libmpv) rather than `video_player`: it forwards custom HTTP headers to every child
request of an HLS playlist, which these CDNs require, and it handles demuxed audio/video.

**A TV box can't afford media_kit's default Android video path.** That default is `--vo=gpu
--hwdec=auto-safe` → `mediacodec-copy`: hardware decode, then every frame copied back to CPU memory
and re-uploaded as a texture. The copy cost scales with resolution, so on a TV's SoC it is fine at
low quality and falls apart on the higher variants — video behind, audio (cheap to keep fed) ahead,
which is what "auto/high stutters and the sound doesn't match" is. `watch_screen.dart` asks for
`--vo=mediacodec_embed --hwdec=mediacodec` on `TvPlatform.isTvDevice` only; the two go together or
not at all, since that output can only present frames MediaCodec itself produced. Subtitles are
unaffected — `libass` is off, so mpv never draws them and `SubtitleView` renders them in Flutter —
but a stream the hardware decoder refuses has nothing to show, so a decoder error from libmpv drops
the player back to the copying path in place (`_recoverFromVideoDecoderError`) instead of failing
the playback. See `docs/playback.md`.

**A libmpv error log is not a playback failure.** media_kit forwards *any* ffmpeg log line at error
level whose text starts with `tcp:` into `Player.stream.error`, and mpv emits those routinely
mid-stream — the canonical one, `tcp: ffurl_read returned 0xdfb9b0bb`, is `AVERROR_EOF`: a
connection that ended before its body did, which libmpv reopens and carries on from. Acting on the
log is what made playback die at random points in a title that was otherwise fine, so it arms a
watchdog instead (`_handleStreamError`): a stalled playhead, not the message, is the signal, and
the response is a re-resolve at the live position with `fresh=1` (backoff and 5-attempt cap
matching `retryCurrentStream()` in `../web/public/scripts/watch.js`), not an error screen. The
budget it protects also had to be widened — media_kit's `network-timeout` default of 5s is five
times tighter than the server proxy's own 25s upstream TTFB allowance. See
[docs/playback.md](docs/playback.md#network-budget-and-stream-recovery).

**libmpv observes `time-pos` unthrottled** — the position stream fires once per decoded frame, and
a `setState` per event rebuilds the whole player screen 50 times a second for values that are all
second-resolution. `_position` is kept exact; the rebuild is gated on the second changing.

Watch parties connect to `wss://…/ws/rooms/:code?token=…` (`lib/core/api/room_socket.dart`) with the
same reconnect and echo-guard behavior as the web frontend's `room-sync.js`.

Chromecast (`lib/core/cast/cast_service.dart`) resolves its receiver app id rather than hardcoding
one: a device-local override (Account → Chromecast, `core/config/cast_receiver_config.dart`) beats
`castReceiverAppId` from `GET /api/cast-config`, which beats `kStreamioReceiverAppId` (`BF64D6B2`,
the shared receiver deployment). The chain deliberately does **not** end at Google's default media
receiver: that one mishandles demuxed audio/video HLS, so an unreachable server would downgrade
into "casts fine, plays wrong" rather than failing visibly. Hardcoding the Streamio id is safe
because that receiver is install-agnostic — it is told which backend to talk to per cast. The
override exists because a receiver is registered against a Google Cast console account, not against
a Streamio install, so the person running the app is not necessarily the person who can change
`CAST_RECEIVER_APP_ID` on the server. **The platform SDK reads the id once per process**, so a
changed id needs an app restart — the settings screen says so when it detects that.

**A cast URL goes in `contentId` as well as `contentUrl`.** CAF plays whichever is set, but the
receiver's LOAD interceptor (`normalizeLoad()` in the `cast-receiver` repo) reads `contentId`
first and sniffs the container format off it — so a raw upstream URL there had it deciding what to
play from one string while playing another. The browser sender and the receiver's own self-issued
loads both put the proxied URL in both fields.

**A cast's `contentType` is lowercase — `application/x-mpegurl`.** CAF chooses its playback
pipeline by looking the string up in its own table, case-sensitively: `application/x-mpegURL`
misses it, the manifest goes to the plain media element, which cannot play a playlist, and the
load fails ~13s in with error 100 (`MEDIA_UNKNOWN`) — and every later load on that receiver page
fails with it, so the receiver's recovery ladder burns all three attempts on a healthy stream.
That is what made a title cast fine from a browser (whose sender always sent it lowercase) and
die from the app. `castContentTypeFor()` in `cast_service.dart` is the only place it is chosen;
`test/cast_content_type_test.dart` pins the spelling. The receiver canonicalizes whatever it
receives, but a receiver deployment can be older than the app, so the sender must be right too.

**A cast never falls back to the raw stream URL.** `/api/cast-config` is allowed to fail, but an
empty `castProxyBase` used to mean the unproxied CDN URL went to the receiver — fetched from the
Chromecast's own IP with no Referer, i.e. a 403 and a cast that connects and then dies. The base
is derived from the server this client is already talking to instead
(`CastService._resolveProxyBase`), the same fallback the receiver applies to a bare `apiBase`.

**A session that is already up still has to be handed the stream.** `castSessionProvider` is
listened to with `fireImmediately`, because a receiver is very often connected *before* the watch
screen exists — cast from the home screen, or open the next episode while the TV is playing — and
a change-only listener never fires for it; `_load()` re-runs the same decision once the stream
resolves, for the case where the session was up but there was nothing yet to send. Without both,
every episode after the first had to be pushed by hand from "Play this on the TV".

**The receiver is handed a `customData` contract, not just a URL.** `core/cast/cast_payload.dart`
mirrors `buildCastCustomData()` in `../web/public/scripts/watch.js`; the receiver — a third repo,
`cast-receiver`, deployed as a static page — uses it to draw its own UI (artwork, title, S/E),
to advance
to the next episode **by itself** once this app is backgrounded or killed, and to re-resolve a
stream whose signed URL expired mid-playback. `episodes` is the show flattened in play order
(ids only, ~40 bytes each) from `flatEpisodesProvider` — the same flatten `nextEpisodeProvider`
uses, extracted so the two can't drift. Subtitle URLs are **proxy-wrapped before sending**: upstream
VTT is usually plain http and never carries CORS, either of which makes CAF drop the track without
a word.

Every field is optional and the receiver degrades field by field, so adding one never needs a
coordinated release — renaming or removing one does. `_buildCastPayload()` is best-effort for the
same reason: a failed show-details fetch (18+ gate, offline) omits fields rather than failing the
cast. `MediaInformation.metadata` stays populated regardless, because Assistant and the media
notification read that and not the receiver's DOM. `docs/protocol.md` in the receiver's repo is the
contract's canonical reference — it is the implementation both senders have to satisfy.

**Controlling a running cast is split across two transports, deliberately.** Play/pause, ±10s and
seek are *standard* Cast media commands through `flutter_chrome_cast`, and need nothing from the
receiver — they work against a device holding a receiver older than the app. **±10s is resolved to
an absolute position here, though**: the plugin's Android bridge silently drops
`GoogleCastMediaSeekOption.relative`, so a relative skip reached the receiver as an absolute seek to
ten seconds in (`CastService.resolveSeekTarget`, `test/cast_seek_test.dart`). Titles, episode
identity and the subtitle/audio track lists come from the receiver's `STATE` broadcast on
`urn:x-cast:com.streamio.control`, every 5s and on each phase change; that is identity resolution,
not transport resolution, so the panel's progress bar runs off `playerPositionStream` and never off
`STATE`. **The control channel needs native code**: `flutter_chrome_cast` exposes no
custom-namespace API at all (no `sendMessage` in its Dart, Kotlin or Swift), so
`core/cast/cast_control_channel.dart` sits on `CastControlChannel.kt`/`.swift`. Both register their
message callback against the *session* and therefore re-attach from a session-manager listener — a
cast resumed from the notification would otherwise leave the panel talking to nothing. **Attaching
also has to be retried**: `CastContext.getSharedInstance()` throws until the SDK is initialized, and
that happens from Dart after a `/api/cast-config` round trip — long after the channel is first
subscribed. Trying once meant no `STATE` for the whole process, which looks exactly like a receiver
that doesn't speak the protocol. `adb logcat -s StreamioCast` shows the attach sequence.
The panel is also reachable from outside the player: `NowCastingButton` sits in the home screen's
top-right corner and draws nothing unless a receiver is connected *and* has media loaded
(`CastControlPanel.hasMedia`, shared with the panel so the two can't disagree). Opened from there it
has no stream of its own, so `onCastHere` is null and `episodes` is empty — "Play this on the TV"
and the episode picker drop out, everything else acts on what the receiver already holds.

**Audio language is the one control that can be legitimately absent**: audio renditions live inside
the HLS manifest rather than in `MediaInformation.tracks`, and the receiver plays through the
device's native pipeline where CAF's JS layer may not see them — `STATE.audioTracks` is then empty
and the panel hides the control. See `docs/playback.md`.

Two Cast requirements live outside Dart and fail silently when missing:
`OPTIONS_PROVIDER_CLASS_NAME` (plus `MediaNotificationService`) in `AndroidManifest.xml`, without
which `CastContext.getSharedInstance()` throws and the button never appears; and
`NSLocalNetworkUsageDescription` + `NSBonjourServices` in `Info.plist`, without which iOS 14+
discovers nothing. The Bonjour list names receiver ids literally, so a custom id other than the two
listed there needs adding for iOS discovery to see it. The Cast button hides itself when the
platform doesn't support Cast or the SDK failed to start; a server that can't answer
`/api/cast-config` no longer disables it.

## Android TV / D-pad

The same APK runs on phones and on TV (`LEANBACK_LAUNCHER` intent filter, `leanback` and
`touchscreen` both `required="false"`), so every screen has to be drivable with nothing but a D-pad
and an OK button.

**`isTv()` (`lib/shared/tv.dart`) asks the platform, not Flutter.** It used to be
`MediaQuery.navigationModeOf(context) == directional`, which looks like the built-in signal and is
not: `navigationMode` is a value the *application* writes onto a `MediaQuery`, defaulting to
`traditional`, and no engine ever reports the platform's into it. It therefore answered `false`
everywhere, including on a real television, which silently disabled every TV path in the app. The
answer now comes from `MainActivity.kt` over the `streamio/platform` method channel
(`UiModeManager` + the leanback/television/touchscreen system features), resolved in `main()`
alongside `AppVersion.load()` so `build` can read it synchronously and the first frame is already
the right layout. The MediaQuery aspect is still honoured, so a subtree — or a test — can still opt
in by hand.

**Directional traversal never crosses a `FocusScope`.** `ShellRoute` has its own `navigatorKey`, so
the shell's `child` is a nested `Navigator` and every page sits in that route's own scope;
`inDirection` only ever considers `nearestScope`'s descendants. From inside a page, the nav chrome
is therefore unreachable at any number of D-pad presses — the top row of the page is simply the
ceiling. `_DirectionalEscapeAction` in `app_shell.dart` overrides `DirectionalFocusIntent`, and when
`FocusNode.focusInDirection` reports it *didn't* move, hands focus to the nav by hand (up for the
top bar, left for the rail). The reverse needs no help: the nav is in the root scope, whose
descendants include the nested one. This is invisible on a touch device and total on a remote —
`test/shell_focus_test.dart` covers both layouts.

**A remote can't leave a text field unaided.** `EditableText` installs its own
`DirectionalFocusAction.forTextField()`, which by design ignores intents with
`ignoreTextFields: true` — and that's what Flutter's app-level arrow bindings send, on the
assumption that Tab moves focus and the arrows belong to the caret. A remote has no Tab, so sign-in
(two fields and a button) was not completable. `_TvTextFieldEscape` in `app.dart` rebinds the
*vertical* arrows to the same intent with `ignoreTextFields: false`; it sits inside
`DefaultTextEditingShortcuts` and so is consulted first. Left/right stay caret movement.

**Arrow keys are focus traversal first.** A `Shortcuts` that binds `arrowLeft`/`arrowRight` and sits
above a row of buttons makes every button past the focused one permanently unreachable by remote,
because the app-level `DirectionalFocusIntent` never gets the key. The watch screen wants both
behaviours, so its seek action is a `_ConditionalCallbackAction` that reports itself *disabled*
while the controls overlay is up on a TV — a disabled action is what lets `Shortcuts` return
`ignored` and the key continue up to the default traversal. Returning early from the callback would
not work; the action would still count as handled.

**Hidden chrome must be focus-excluded, not just pointer-excluded.** A faded-out overlay still holds
focusable buttons, and a remote will happily spend presses on controls nobody can see. Anything
wrapped in `IgnorePointer` for a hidden state wants `ExcludeFocus` too — and something else has to
take focus when it does, since a screen with no focused node swallows the next D-pad press.

**`autofocus` fires once, when a node is created.** Nodes that outlive a hide/show cycle need an
explicit `requestFocus()` on re-show.

Focus has to be legible from three metres: `AppTheme` sets `focusColor` and per-family button
`overlayColor` to the accent at ~32% (Material's ~8% white default is invisible on this dark theme),
and `TvFocusable` (`lib/shared/widgets/tv_focusable.dart`) is the baseline for card-like widgets —
ring, scale, and `Scrollable.ensureVisible`, which walks *all* nested scrollables.

The TV shell (`routing/app_shell.dart`) replaces the top nav bar with a side rail, so anything
reachable only from that bar's `IconButton`s — Providers, Watch parties — has to be repeated on the
rail or it becomes unreachable with a remote.

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
the API client's contracts (401-refresh-replay, concurrent 401s sharing one refresh since
refresh tokens rotate and are single-use, redirect following, path-prefixed bases), and the account
paging arithmetic, whose failure mode is duplicate rows for 18+-filtered accounts rather than an
error (`account_paging_test.dart`, `paged_response_test.dart`).

## Branding

The launcher icon is the website's own mark, copied from `../web/public/icons/site-icon.png` to
`assets/icon/site-icon.png`, with two derived variants: `app-icon.png` (mark at 72% on white,
flattened to RGB — iOS rejects an alpha channel) and `app-icon-foreground.png` (mark at 74% on
transparent, for Android's adaptive icon; `flutter_launcher_icons` adds a 16% inset). Re-run
`dart run flutter_launcher_icons` after changing the art. In-app, `lib/shared/widgets/app_logo.dart`
draws the same mark through a `srcIn` tint — the source art is black and would be invisible on the
dark theme, which only works because the mark is monochrome.

The type — Bebas Neue for display, DM Sans for body, the web app's own pairing — is **bundled, not
fetched**. `google_fonts` defaults to downloading on first use and caching on device, which renders
the whole app in Flutter's fallback face on a first launch with no DNS; `main()` sets
`allowRuntimeFetching = false` and the files live in `assets/google_fonts/`. They are matched **by
filename** (`DMSans-Medium.ttf` — the Google Fonts API's own naming), so they must not be renamed,
and a weight that `AppTheme` asks for and the folder doesn't carry is a font that silently doesn't
render. `test/fonts_test.dart` guards the filenames; a *new* weight shows up as an "unable to load
font" line at startup. The OFL text sits next to the fonts and is registered with the
`LicenseRegistry` in `main()`.
