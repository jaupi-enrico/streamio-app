# Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift database code
flutter run
```

## Server address

On first launch the app asks for the server address (a DDNS name, the Cloudflare Tunnel URL, or a
LAN address). There is **no compile-time base URL** — a Streamio install is self-hosted and its
address changes per deployment, so the value is typed in and stored in `shared_preferences`
(`lib/core/config/server_config.dart`). It can be changed later from Account → Server.

The address is validated with `GET {base}/health`. If the tunnel is up but still showing its
waiting page, the screen says so and offers to save the address anyway rather than refusing it.

## Path-prefixed installs

A path prefix is supported and preserved. An install mounted behind a reverse proxy at
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

## Linux desktop

The `linux/` embedder is checked in, so `flutter run -d linux` / `flutter build linux` work like
any other Flutter target as long as the toolchain is present:

```bash
sudo pacman -S clang cmake ninja pkgconf gtk3        # Arch; Debian/Ubuntu: clang cmake ninja-build pkg-config libgtk-3-dev
flutter doctor                                        # confirm "Linux toolchain" is a check
flutter run -d linux                                  # debug run
flutter build linux --release                         # release bundle: build/linux/x64/release/bundle/
```

`media_kit_libs_video` vendors its own `libmpv` for the bundled build, so nothing extra is needed
for playback beyond the toolchain above.

**NVIDIA + Wayland: blue video, not a black/red screen.** The app window itself renders fine; only
the `Video` widget in `watch_screen.dart` comes up solid blue. That's `media_kit_video`'s
hardware-accelerated (ANGLE/EGL) texture path, which is broken against the NVIDIA proprietary
driver's GBM/Wayland integration — the fix (already applied) is `VideoController` on Linux
constructed with `VideoControllerConfiguration(enableHardwareAcceleration: false)`, forcing
software-decoded frames into the texture instead. If a *different* rendering glitch shows up on
NVIDIA/Wayland (not the video itself, but window compositing), try forcing XWayland as a
diagnostic: `GDK_BACKEND=x11 flutter run -d linux`.

## Other commands

```bash
flutter analyze                       # expected to be clean
flutter test
flutter build apk --debug             # catches native/plugin breakage analyze can't
dart run flutter_launcher_icons       # after changing assets/icon/
```
