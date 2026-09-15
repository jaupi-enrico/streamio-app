# Streamio — Flutter client

A Flutter client for a self-hosted Streamio server (`../web`). It covers the same ground as the
web frontend — home, catalog, search, providers, details, playback, account, social, watch
parties, admin — and adds offline downloads.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift database code
flutter run
```

Documentation has moved to [`docs/`](docs/README.md):

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Playback](docs/playback.md)
- [Offline downloads](docs/offline-downloads.md)
- [Testing](docs/testing.md)
- [Branding](docs/branding.md)
- [Releasing](docs/releasing.md)
- [History](docs/history.md)

## License

Copyright © 2026 Enrico Jaupi. Released under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) — share and adapt it freely
for **non-commercial** purposes, with credit, and license what you build from it under the same
terms. Full text in [`LICENSE`](LICENSE).

The server this client talks to (`../web` throughout the docs) is a separate project and is not
part of this repository.
