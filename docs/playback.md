# Playback

`media_kit` (libmpv) rather than `video_player`: it forwards custom HTTP headers to every child
request of an HLS playlist, which these CDNs require, and it handles demuxed audio/video.

## vixcloud proxying

Fetched directly, vixcloud's CDN sees whatever Referer/Origin the client sends and intermittently
403s depending on the edge node. The app (`features/watch/watch_providers.dart`, and the download
manager's 403 fallback) routes it through `{base}/api/cast-proxy?direct=1&url=` — a port of
`needsSourceProxy()` in `../../web/public/scripts/watch.js` — which refetches server-side with a
fixed Referer/UA and rewrites every nested manifest URI. This applies whenever the host is
`vixcloud.co` or the URL is plain `http://`.

## Watch parties

Watch parties connect to `wss://…/ws/rooms/:code?token=…` (`lib/core/api/room_socket.dart`) with
the same reconnect and echo-guard behavior as the web frontend's `room-sync.js`.

## Chromecast

Chromecast uses the deployment's own receiver app id from `GET /api/cast-config`, not a
hardcoded one; the Cast button hides itself when the platform or the server doesn't support it.
