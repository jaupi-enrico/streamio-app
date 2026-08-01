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
