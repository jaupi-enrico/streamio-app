# Testing

```bash
flutter test
flutter test test/hls_parser_test.dart                     # one file
flutter test test/api_client_test.dart --plain-name 'redirect'   # one group/test
```

`test/` covers the places where a wrong answer is silent rather than loud: HLS parsing (demuxed
audio, AES-128, URI resolution), the encrypt → ranged-decrypt round trip offline seeking depends on,
and the API client's contracts (401-refresh-replay, concurrent 401s sharing one refresh since
refresh tokens rotate and are single-use, redirect following, path-prefixed bases).

`flutter analyze` cleanliness is a maintained property. `flutter build apk --debug` is worth
running after dependency or platform-config changes — it catches plugin and manifest breakage the
analyzer cannot see.
