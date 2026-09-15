# Streamio — Flutter client docs

A Flutter client for a self-hosted Streamio server (`../../web`). It covers the same ground as
the web frontend — home, catalog, search, providers, details, playback, account, social, watch
parties, admin — and adds offline downloads.

- [Getting started](getting-started.md) — running it, first-launch server setup, path-prefixed
  installs
- [Architecture](architecture.md) — layers, auth, the provider graph
- [Playback](playback.md) — `media_kit`, the source proxy, watch parties, Chromecast
- [Offline downloads](offline-downloads.md) — fetching, storage, encryption, local playback
- [Testing](testing.md) — what `test/` covers and why
- [Branding](branding.md) — the launcher icon and in-app logo
- [Releasing](releasing.md) — cutting and shipping a new build
- [History](history.md) — the scraping engine this app used to carry, and why it's gone

See `../CLAUDE.md` for guidance aimed at Claude Code specifically (commands, invariants, and
conventions to follow when changing this codebase). `../../web/CLAUDE.md` documents the backend
this app talks to — read it before changing anything that crosses the wire.
