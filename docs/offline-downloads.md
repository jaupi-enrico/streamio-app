# Offline downloads (`lib/core/download/`)

A download is playable with no network and is not a file the rest of the device can use.

## Fetching

`download_manager.dart` — resolve the stream, parse the master playlist, take the video variant
plus its demuxed audio rendition, and pull every segment with a bounded worker pool and retries.
Each segment is a database row, so an interrupted download resumes segment-by-segment instead of
restarting. Segment URLs are signed and short-lived, so a resume re-resolves the stream and
re-points the pending rows at fresh URLs. A 403 from the CDN falls back to the server's
`/api/cast-proxy`, the same workaround the web player uses.

## Storage

`segment_store.dart` — segments land in the app-private support directory, AES-CTR encrypted
under a 256-bit key generated on first use and kept in the platform keystore. **CTR specifically
because it is seekable** — a byte offset maps to a counter block. Upstream HLS AES-128 is undone
at download time so an expiring CDN key can't lock the user out later.

## Playback

`local_media_server.dart` — an HTTP server on `127.0.0.1` (ephemeral port, random per-launch path
token, running only during playback) synthesizes a master playlist, one media playlist per track,
and range-aware segment bodies, decrypting on the fly.

## What this does and doesn't mean

The files are invisible to other apps, the gallery and file managers, and a segment copied off the
device is unplayable without the keystore key. It is not DRM against the device's owner and isn't
presented as such.

**Known limitation:** downloads run in-process — leaving or force-quitting the app pauses them; no
foreground service is wired up. Progress recorded while watching offline is stored locally and
pushed to `POST /api/account/history` when the server is next reachable (`offline_sync.dart`).

State: `lib/state/download_providers.dart`; schema in `lib/core/db/app_database.dart`.
