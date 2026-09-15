# Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift database code
flutter run
```

## Server address

On first launch the app asks for the server address (a public hostname or a LAN address). There is
**no compile-time base URL** — a Streamio install is self-hosted and its address changes per
deployment, so the value is typed in and stored in `shared_preferences`
(`lib/core/config/server_config.dart`). It can be changed later from Account → Server.

The address is validated with `GET {base}/health`. If the address answers but the install is still
showing a waiting page, the screen says so and offers to save it anyway rather than refusing it.

## Path-prefixed installs

A path prefix is supported and preserved. An install mounted behind a reverse proxy at
`https://example.com/streamio` works: every URL the app builds appends to the stored base,
so requests land on `.../streamio/api/…`, `.../streamio/health` and `wss://.../streamio/ws/rooms/…`.
If the address pasted in is a page URL rather than the base (`.../streamio/watch`, copied out of a
browser mid-browse), the probe walks the path back one segment at a time and saves whichever base
actually answered.

Two things on the **server** side have to agree with that prefix when you mount the app under one:

- the reverse proxy must strip the prefix before forwarding, since the backend registers its
  routes at the root (`/api/…`, `/health`, `/ws/rooms/…`);
- `APP_URL` must include the prefix. It's what `content.router.ts` builds `CAST_PUBLIC_BASE` from
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
software-decoded frames into the texture instead. If a _different_ rendering glitch shows up on
NVIDIA/Wayland (not the video itself, but window compositing), try forcing XWayland as a
diagnostic: `GDK_BACKEND=x11 flutter run -d linux`.

### Installing the release build

`flutter build linux --release` doesn't produce an installer — there's no packaging config
(`.desktop` file, `.deb`, AppImage, Flatpak manifest) checked in for this project. What you get is
`build/linux/x64/release/bundle/`: a **self-contained, relocatable** directory (the `streamio`
binary, its bundled `lib/*.so` — including `libmpv` from `media_kit_libs_video` — and `data/` for
assets/ICU). It only runs in place relative to its own `lib/`; there's nothing to `make install`.

To actually install it for one machine:

```bash
# 1. Copy the bundle somewhere permanent — don't run it from build/, a clean
#    rebuild wipes that directory.
sudo mkdir -p /opt/streamio
sudo cp -r build/linux/x64/release/bundle/* /opt/streamio/

# 2. Put the binary on PATH (a symlink is fine since the binary locates its
#    own lib/ and data/ next to itself, not relative to $PWD).
sudo ln -sf /opt/streamio/streamio /usr/local/bin/streamio

# 3. Optional: an app-launcher entry, so it shows up like any installed app.
sudo cp assets/icon/app-icon.png /opt/streamio/streamio.png
cat <<'EOF' | sudo tee /usr/share/applications/streamio.desktop
[Desktop Entry]
Type=Application
Name=Streamio
Exec=/opt/streamio/streamio
Icon=/opt/streamio/streamio.png
Categories=AudioVideo;Player;
EOF
```

`/opt` + `/usr/local/bin` + `/usr/share/applications` needs `sudo`; a per-user install works the
same way rooted at `~/.local/share/streamio`, `~/.local/bin`, and `~/.local/share/applications`
instead — no root required, and `~/.local/bin` just needs to be on `PATH`.

There's no update channel for the Linux build — re-run the copy step after every
`flutter build linux --release` you want installed. (The in-app updater in
`docs/releasing.md` is Android-only: it checks `/api/settings/client-version` and installs an
APK, which doesn't apply here.)

`scripts/install-linux.sh` automates all of the above from a checkout (`--user` for the per-user
layout, `--skip-build` to reuse an existing bundle); `scripts/uninstall-linux.sh` reverses it.

### Handing it to someone else

To distribute it to a machine that has no Flutter toolchain, package it instead:

```bash
./scripts/package-linux.sh          # dist/streamio-<version>-linux-x64.tar.gz
                                    # dist/streamio_<version>-<build>_amd64.deb (if dpkg-deb is installed)
```

The tarball is the bundle plus a self-contained `install.sh`/`uninstall.sh` and a README — the
recipient extracts it and runs `./streamio` directly, or `./install.sh` (`--user` for no-sudo) for
an app-menu entry and a `streamio` on `PATH`. The `.deb` installs the same layout
(`/opt/streamio`, symlink in `/usr/bin`, hicolor icon) through the package manager. Only GTK 3 is
needed on the target; `libmpv` rides along inside the bundle. See `docs/releasing.md` for how
these get attached to a GitHub release.

The Windows equivalent is `scripts/package-windows.ps1`, which has to run on Windows — Flutter
cannot cross-compile that target.

## Other commands

```bash
flutter analyze                       # expected to be clean
flutter test
flutter build apk --debug             # catches native/plugin breakage analyze can't
dart run flutter_launcher_icons       # after changing assets/icon/
```
