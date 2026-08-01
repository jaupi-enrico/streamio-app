# Architecture

The app is a thin client: it does **not** scrape. An earlier iteration ported the backend's engine
to Dart; that is gone (see [History](history.md)) — `lib/core/models/` is what survived it.

| Layer | Where |
|---|---|
| HTTP + auth (bearer token, one silent refresh on 401, replay) | `lib/core/api/api_client.dart` |
| One class per backend router | `lib/core/api/{content,auth,account,social,rooms,settings}_api.dart` |
| Wire format → domain models | `lib/core/api/json_mappers.dart` |
| Domain models (mirror `../../web/core/models/*.ts`) | `lib/core/models/` |
| Riverpod graph, rooted at the server URL | `lib/state/` |
| Screens | `lib/features/<feature>/` |
| Routing, guards, responsive shell | `lib/routing/` |

**Deserialization is split, deliberately.** The **domain** models (`Movie`, `TvShow`, `Episode`,
`Season`, `Genre`, `People`, `Category`, `PlaybackSource`) mirror `../../web/core/models/*.ts`
field-for-field and are parsed by `core/api/json_mappers.dart`, which keeps those classes free of
wire-format concerns — that file is the single place that knows the camelCase shape, the ISO date
strings, and the fact that `/api/shows/:id` has no discriminator (it keys off `seasons`). The
**account/social** types (`AppUser`, `LibraryEntry`, `HistoryEntry`, `Share`, `Room`,
`HostingPoint`, ...) carry their own `fromJson`, because they are snake_case Postgres rows with no
TypeScript counterpart to stay aligned with.

## The provider graph is rooted at the server URL

There is no compile-time base URL: a Streamio install is self-hosted and its address changes per
deployment, so the user types it in on first run (`core/config/server_config.dart`,
`features/setup/`) and it is stored in `shared_preferences`. `apiClientProvider` watches it, so
changing the server disposes the client and every content/account provider with it and the app
repoints without a restart. Anything reading `apiClientProvider` before a server is set throws
`ServerNotConfigured`; the router's redirect keeps that unreachable.

## Every screen requires an account

`routing/app_router.dart` inverts the usual guard: only `/login`, `/register`,
`/reset-password`, `/verify-email` and `/server` are reachable signed out, and everything else —
browsing, details, playback, downloads — redirects to `/login` with a `redirect=` back to where
you were. This is why `AuthNotifier.isBootstrapped` exists: the guard has to tell "still restoring
the stored session" (hold on the splash) from "signed out" (go to `/login`), and it can't use
`isLoading` for that, because signing in passes through `loading` too. It's also why a failed
`/api/account/me` falls back to the profile cached in the keystore — an offline launch must not
lock the user out of their downloads.

## Cross-cutting invariants

These span both projects; changing one side alone breaks things in ways local tests won't catch.
The backend half of each is described in `../../web/CLAUDE.md`.

- **Native auth.** The web frontend keeps its refresh token in an httpOnly cookie, which a native
  client cannot use. Tokens live in the platform keystore (`flutter_secure_storage`). The app sends
  `X-Client: app`, and `sendTokens` in `../../web/routes/auth.router.ts` then also returns the
  refresh token in the JSON body and accepts it back in the body on `/refresh` and `/logout`. OAuth
  works the same way via an allowlisted `redirect_uri=streamio://auth`. Browser behavior must stay
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
- **Path-prefixed installs.** See [Getting started](getting-started.md#path-prefixed-installs).
  Never build a URL with `Uri.replace(query: '')` (it emits a trailing `?#` that then prefixes
  every path).
- **vixcloud must be proxied.** See [Playback](playback.md).
- **Resolved streams are never cached.** `POST /api/episodes/:id/video` returns signed URLs that
  expire in minutes. Re-resolve per playback attempt; a paused download must re-resolve before
  resuming, because its stored segment URLs are dead.
