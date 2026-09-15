# Playback

`media_kit` (libmpv) rather than `video_player`: it forwards custom HTTP headers to every child
request of an HLS playlist, which these CDNs require, and it handles demuxed audio/video.

## Android TV video output

media_kit's Android default is `--vo=gpu --hwdec=auto-safe`, which resolves to `mediacodec-copy`:
MediaCodec decodes in hardware, then every frame is copied back into CPU memory and re-uploaded as
a GPU texture. A phone absorbs that; a TV box (quad-A53, shared memory bandwidth) does not. At
1080p that's ~3 MB per frame down and back up, the video pipeline falls behind while the audio
output — which costs nothing to keep fed — plays on, and the picture ends up stuttering *and*
drifting out of sync with the sound. Because the copy cost scales with resolution, it only shows up
on the higher variants: "auto" and "high" break where a lower quality plays fine.

`watch_screen.dart` therefore asks for `--vo=mediacodec_embed --hwdec=mediacodec` when
`TvPlatform.isTvDevice` — MediaCodec is handed the output surface directly and decoded frames never
leave the GPU. Phones keep media_kit's default, which is the more compatible of the two.

Two things make that safe. Subtitles are unaffected: `PlayerConfiguration.libass` is `false`, so
mpv renders no subtitles at all and media_kit's `SubtitleView` draws them in Flutter from
`player.stream.subtitle` — nothing depends on mpv compositing them into the frame. And the narrower
path degrades rather than fails: `mediacodec_embed` can only present frames MediaCodec itself
produced, so a stream the hardware decoder refuses (an unusual profile, 10-bit HEVC on an older
box) would leave a black picture over playing audio. libmpv reports the refusal from its decoder
first, and `_recoverFromVideoDecoderError` switches the player back to the copying path in place —
a decoder reinit, not a re-resolve of the signed URL — and remembers it for the rest of the session.

Relatedly, libmpv observes `time-pos` unthrottled, so the position stream fires once per decoded
frame. The watch screen keeps its `_position` field exact but only calls `setState` when the whole
second changes: everything the position drives has one-second resolution, and a full rebuild 50
times a second is a meaningful share of a TV box's UI budget, spent competing with the decode.

## Network budget and stream recovery

Every fragment travels device → proxy hops → server → upstream CDN, and
`/api/cast-proxy` cannot emit a byte until the CDN has answered *it*. Time-to-first-byte is the sum
of that chain, and the server gives itself **25s** to reach first byte upstream before aborting
with a 504 (`content.router.ts`). The web player is tuned for it: hls.js gets 30s TTFB, 120s total
load, four timeout retries and six error retries per fragment.

media_kit sets **`network-timeout: 5`** on every player it creates. That is a general-purpose
default and five times tighter than the server's own upstream budget, so the app was tearing down
connections the server was still legitimately servicing. `watch_screen.dart` raises it to 30s
(`_networkTimeoutSeconds`), matching the web player and sitting above the proxy's abort, so a dead
upstream arrives as the proxy's 504 rather than as a client-side timeout.

FFmpeg's `reconnect`/`reconnect_streamed` are deliberately *not* set alongside it. They would have
to go through `demuxer-lavf-o`, a single string media_kit already populates (`protocol_whitelist`
among others) that cannot be appended to without freezing this version's contents — and
libavformat's HLS demuxer forwards only a fixed whitelist of options to the connections it opens
for child playlists and segments. `reconnect` is not on that list; `rw_timeout`, which is what
`network-timeout` becomes, is.

**A libmpv error log is not a playback failure, and treating it as one is what killed playback
mid-title.** media_kit forwards *any* ffmpeg log line at error level whose text starts with `tcp:`
into `Player.stream.error` (see `errorController` in its `native/player/real.dart`), and mpv emits
those routinely: a keep-alive connection the CDN closed between segments, a read cut short, a fetch
that outran the socket timeout. The canonical one is `tcp: ffurl_read returned 0xdfb9b0bb` — that
hex is `AVERROR_EOF` (the FFmpeg tag `'EOF '`), i.e. "the connection ended before the body did".
libmpv reopens and carries on; the screen used to be replaced by an error the moment the *log*
arrived.

So the log arms a watchdog rather than deciding anything (`_handleStreamError`):

- give the player **6s** to keep going by itself (2s if nothing has played yet — no playback to
  protect, no reason to sit on a spinner). Further errors during that window are ignored; mpv
  reports them in bursts and re-arming per error would postpone the decision indefinitely;
- if the playhead advanced, the error was noise — clear the "Reconnecting…" banner and do nothing.
  If the viewer *paused*, that is not a stall either; a genuinely dead stream produces a fresh
  error when they resume;
- otherwise re-resolve the current server and resume at the live playhead, with the same backoff
  and 5-attempt cap as the web player's `retryCurrentStream()`. Only after those are spent does the
  error reach the screen — carrying libmpv's own message, as before.

The re-resolve passes **`fresh=1`**, and that is the part with no visible failure mode: the backend
caches resolves and these URLs are signed and expire in minutes, so a retry without the flag is
handed back the identical dead URL for the rest of the TTL and fails five times in exactly the same
way. `test/resolve_video_fresh_test.dart` pins it. Resuming from the live `_position` rather than
the stored progress row matters for the same reason the retry exists — the row lags by up to ten
seconds, and a stream that fails repeatedly would walk the viewer backwards.

Offline playback is exempt: it is served by this app's own loopback server, so there is no network
to recover from and a failure there (a missing or undecryptable segment) is a real one.

## Source proxying

Fetched directly, some CDNs see whatever Referer/Origin the client sends and intermittently 403
depending on the edge node. The app (`features/watch/watch_providers.dart`, and the download
manager's 403 fallback) routes it through `{base}/api/cast-proxy?direct=1&url=` — a port of
`needsSourceProxy()` in `../../web/public/scripts/watch.js` — which refetches server-side with a
fixed Referer/UA and rewrites every nested manifest URI. This applies whenever the URL is plain
`http://`, **or the resolve came back with headers at all** — headers on a source mean the upstream
demands a `Referer`/`Origin` no client can set on its own request, which is the only thing that
covers a source whose CDN hostnames are generated fresh per resolve and so can never be matched by
a host list.

Those two rules are the whole decision by default, exactly as in the web player. A deployment that
meets a CDN which 403s a direct fetch *without* the resolve asking for any header can pin that host
at build time — `--dart-define=STREAMIO_PROXY_HOSTS=cdn.example.net,edge.example.org`,
comma-separated, matched as a suffix so `example.net` covers `cdn.example.net` too.
`scripts/release.sh` and `scripts/package-linux.sh` / `package-windows.ps1` pass it through from
the environment (set it in the gitignored `scripts/release.env`), so no host list is carried in
this repository.

A `Referer` the resolver asked for is forwarded to the proxy as `ref=`, ahead of `url=`. The
proxy's default is the media host's own origin, which some edges 403 outright,
and the server threads the override into the prefix it rewrites child URIs with — so it covers the
segments and not just the playlist. It applies to cast URLs and cast subtitle URLs as much as to
local playback: leaving it off is what made a title cast fine from a browser and die with a media
error from the app. `refererOf` and `proxiedSourceUrl` build it locally,
`CastService.castProxyBase` for cast; `test/cast_proxy_url_test.dart` pins both shapes.

## Watch parties

Watch parties connect to `wss://…/ws/rooms/:code?token=…` (`lib/core/api/room_socket.dart`) with
the same reconnect and echo-guard behavior as the web frontend's `room-sync.js`.

## Chromecast

Chromecast uses the deployment's own receiver app id from `GET /api/cast-config`, not a
hardcoded one; the Cast button hides itself when the platform or the server doesn't support it.

### What triggers a LOAD

**Connecting to a device and giving it something to play are one intent**, so the LOAD fires off
the session going active (`_wireCastAutoLoad` in `watch_screen.dart`), not off picking a device —
the same shape as the web sender, whose `onCastSessionStarted` loads for `SESSION_STARTED` *and*
`SESSION_RESUMED`. `CastSheet` therefore only connects.

Keeping the LOAD inside the device picker is a trap worth naming, because it looks correct: a
session can become active without this app initiating it — resumed from the media notification, or
joined because the receiver is *already running on the TV*, launched before anything was cast to
it. In that state the picker has nothing left to do (starting a second session on a device that
already has one fails), so there was no way at all to hand the receiver a stream. Tapping the
already-connected device, and the "Play this on the TV" button the panel shows while the receiver
is idle, both call the same `_castCurrentStream`.

The guard against a *duplicate* LOAD is a flag (`_castHandedOff`), not the session id: the id can
be null for a whole session on some platforms, and the receiver honours a second LOAD by restarting
the stream from the beginning.

### Controlling a running cast

The controls (`features/watch/cast_control_panel.dart`) are split across two transports, and the
split is not cosmetic:

- **Transport** — play/pause, ±10s, absolute seek, position — is the *standard* Cast media
  channel, straight through `flutter_chrome_cast`. It needs nothing from the receiver (which
  intercepts only LOAD and advertises `SEEK`/`PAUSE` in `supportedCommands`), so it keeps working
  against a Chromecast holding a receiver older than the app.
- **Identity and tracks** — title, episode, subtitle and audio track lists — is the Streamio
  `urn:x-cast:com.streamio.control` channel, broadcast as `STATE` every 5s and on every phase
  change. Far too coarse for a progress bar, which is why the bar runs off
  `playerPositionStream` instead.

**±10s is resolved to an absolute position by the sender, not sent as a relative seek.** The Cast
protocol has a relative seek and `GoogleCastMediaSeekOption` exposes it, but the plugin's Android
bridge (`GoogleCastSeekOptionsBuilder.fromMap`) reads `position`, `resumeState` and `seekToInfinity`
and never looks at `relative` — so `seekBy(+10s)` arrived at the receiver as
`MediaSeekOptions.setPosition(10s)`, an *absolute* seek to ten seconds in. From anywhere in a film,
"forward 10" jumped to 0:10 and "back 10" pinned playback to the start; iOS honours the flag, so the
bug was Android-only. `CastService.seekBy` now computes the target itself
(`CastService.resolveSeekTarget`, pinned by `test/cast_seek_test.dart`) from `playerPosition` — the
media channel's own clock, 500ms on Android and 1s on iOS, not the 5s `STATE` — clamped to the
stream and stopped two seconds short of the end, which would otherwise end playback. The panel
passes the position it is *displaying* rather than the last tick, so two quick taps skip twenty
seconds.

**The panel remembers what it cast, because on Android nothing else carries a duration.** Two holes
in the plugin's Android bridge meet: `GoogleCastMediaInfo.fromMap` builds the `MediaInfo` without
ever calling `setStreamDuration`, so the duration handed to `CastService.load` is dropped before it
reaches the receiver, and the duration that comes back in the media status arrives only if the
receiver worked one out for itself. Pair that with a receiver that isn't answering on
`urn:x-cast:com.streamio.control` — an older build cached on the device, a bridge that didn't attach
— and the panel had *no* duration at all: a progress bar with no scale, a dead thumb, `00:00` on the
right, over a stream that was playing fine. `CastService.lastLoad` keeps the title, subtitle,
duration and payload of the last LOAD, and the panel consults it **last**, behind `STATE` and behind
the media status, either of which corrects it the moment it arrives. It is cleared on `disconnect`
so a new session never inherits the old numbers; it can still go stale inside one (the receiver
advances episodes by itself), which is why it is the last resort and not the first. When even that
is empty the bar says `--:--` rather than `00:00` — an unknown duration is not a zero one.

An error on the control channel is swallowed rather than surfaced (`CastControlChannel.messages`
handles it and logs once). A `StreamProvider` that ends in error *stays* in error, so one bad moment
would otherwise take the panel's identity half down for the rest of the process — silently and
permanently — while the transport half kept working.

**The progress bar owns the position it draws.** A `Slider` fed straight from the position stream
cannot be dragged: `onChanged` has to store the dragged value or the thumb springs back to the
stream's on the very next frame, which is what made the bar impossible to aim. The panel keeps
three overrides in `_displayPosition` — the drag in progress, an arrow-key scrub (a remote gets to
scrub the bar at ±10s a press; Flutter's own `Slider` key handling steps a tenth of the range,
twenty minutes on a feature film, and fires a seek per press), and the seek in flight, held until
the transport reports a position within three seconds of the target so the bar doesn't rubber-band
back to where the seek started.

**The control channel has to keep trying to attach, and this was the bug behind every "the panel
knows nothing" symptom.** `CastContext.getSharedInstance()` throws until the Cast SDK is
initialized, and the app initializes it *from Dart* — `CastService.initialize` resolves the receiver
id over `/api/cast-config` first. The Flutter side subscribes to this channel as soon as anything
watches `castStateProvider`, which is well before that lands. `CastControlChannel.kt` used to try
once: no context at that instant meant the session-manager listener was never registered and **no
`STATE` ever arrived again for the life of the process** — silently, because everything on this
channel is advisory. On a real device that is a panel with working transport and nothing else: no
title, no duration, no subtitle/audio/episode controls, for every cast. It now retries once a second
for a minute and logs what happened under the `StreamioCast` tag — `no CastContext after 60s;
giving up` is Play services or a missing `OPTIONS_PROVIDER_CLASS_NAME`, `listening for cast
sessions` / `attached to <device>` / `first message on urn:x-cast:com.streamio.control` is the
healthy sequence. The first `HELLO` still routinely races the session handshake, so Dart re-sends it
when a session appears and the native side retries a failed send once.

**That channel needs native code**, because `flutter_chrome_cast` exposes no custom-namespace API
at all — no `sendMessage` in its Dart, Kotlin or Swift. `core/cast/cast_control_channel.dart` sits
on `CastControlChannel.kt` / `CastControlChannel.swift`, which register a message callback against
the *session*: it dies with the session, so both re-attach from a session-manager listener or a
cast resumed from the notification leaves the panel talking to nothing.

**The panel must never gate transport controls on `STATE`.** That split is the whole point: if
"is anything loaded" is answered from `STATE`, then a receiver that plays fine but can't be reached
on the custom namespace — an older build cached on the device, a native bridge that failed to
attach — shows *no controls at all*, even though play/pause and ±10s would have worked. `_hasMedia`
therefore reads the media status first and consults `STATE` only as a second, positive signal (it
knows about a stream being resolved, which the media status calls idle). Only the pickers, which
genuinely need to know what tracks exist, are hidden without a `STATE`.

**Audio language is the one control that can be genuinely unavailable.** Audio renditions live
inside the HLS manifest, not in `MediaInformation.tracks`, so only the receiver can enumerate them
— and it plays through the device's *native* pipeline, where CAF's JS layer may not see them at
all. `STATE.audioTracks` is then empty and the panel hides the control rather than offering an
empty picker. `[CAST-RECEIVER] audio tracks n=` in the backend's logs is how to tell that apart
from a bug.

**Getting back to the controls from outside the player** is `NowCastingButton`
(`features/watch/now_casting_button.dart`), in the home screen's top-right corner. It renders
*nothing at all* unless a receiver is connected and has media loaded — it answers that with
`CastControlPanel.hasMedia`, the same function the panel uses, so the two cannot disagree — because
an always-present cast button would be a different feature (start a cast), and these screens have no
stream to start one with. Casting begins on the watch screen and the app then usually leaves it, so
without this the only route back to play/pause and seek was to reopen the exact title that was cast.

It opens the same panel, with `onCastHere` null and `episodes` empty: there is no local stream to
hand the receiver and no queue to label, so "Play this on the TV" is not offered and the episode
*picker* is hidden. Everything else acts on what the receiver holds and works unchanged —
next/previous episode included, since the queue lives on the receiver and stepping through it needs
only `STATE.episodeIndex`. Dropping the widget on another screen is one line; it is on the home
screen because that is where the app lands.

**Two things the panel must never do with a receiver's own status.** It must not *enforce* the busy
phases: the receiver reports `LOADING` for a second or two after every seek, and greying the
transport out for it made the panel eat every other press of ±10s — tap, watch the buttons go grey,
tap again into a dead control. Busy is now drawn as a ring around play/pause and nothing more; only
"nothing is loaded" disables anything. And it must not repeat `playerState` verbatim: a media status
arrives only when something *changes*, so a `BUFFERING` one stands until the next change, and the
panel went on saying "Buffering…" over a stream that had recovered and was playing at real speed —
which is what "stuck on buffering" turned out to be. The word is gated on the position having
actually stopped moving for three seconds (`_stalled`); the receiver's own `RESOLVING`/`RECOVERING`/
`ERROR` phases are still shown as they arrive, since during those the position genuinely is stopped.

While casting, the local player is paused, so `_saveProgress` has nothing to record; history is
written from `STATE` instead (`_saveCastProgress`, every 30s). It uses the receiver's `episodeId`,
not `widget.id` — the receiver advances episodes by itself, and crediting progress to the episode
the user opened would leave the one actually playing unwatched.
