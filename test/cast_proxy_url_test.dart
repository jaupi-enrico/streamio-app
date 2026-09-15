import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/features/watch/watch_providers.dart';

/// Stands in for whatever a deployment passes in
/// `--dart-define=STREAMIO_PROXY_HOSTS`.
const _pinned = ['media.example.net', 'edge.example.org'];

/// The proxy rules the app and `../web/public/scripts/watch.js` have to agree
/// on. Getting one wrong is silent on this side and fatal on the CDN's: the
/// manifest loads and every segment 403s, or the cast connects and dies with a
/// media error, while the same title plays fine in a browser.
void main() {
  group('needsSourceProxy', () {
    test('plain http is proxied — the receiver page is https', () {
      expect(needsSourceProxy('http://cdn.example/master.m3u8'), isTrue);
    });

    test('a pinned host is proxied, subdomains included', () {
      for (final url in [
        'https://media.example.net/playlist/1?token=a',
        'https://cdn.media.example.net/hls/master.m3u8',
        'https://EDGE.example.org/v2/stitch/x.m3u8',
      ]) {
        expect(needsSourceProxy(url, pinnedHosts: _pinned), isTrue,
            reason: url);
      }
    });

    test('a plain https source is left alone', () {
      expect(needsSourceProxy('https://cdn.example/master.m3u8'), isFalse);
      expect(needsSourceProxy('https://other.example/master.m3u8',
              pinnedHosts: _pinned),
          isFalse);
    });

    test('the pin matches whole labels, not any old substring', () {
      // Ends with the pinned string, but is a different site.
      expect(
        needsSourceProxy('https://notmedia.example.net/a.m3u8',
            pinnedHosts: _pinned),
        isFalse,
      );
    });

    test('nothing is pinned by default', () {
      // No `--dart-define=STREAMIO_PROXY_HOSTS`, so the scheme and the
      // resolver's headers are the whole decision — the same rules the web
      // player applies.
      expect(pinnedProxyHosts, isEmpty);
    });

    test('parses the STREAMIO_PROXY_HOSTS form', () {
      expect(parseProxyHosts(' A.example.net , b.example.org ,,'),
          ['a.example.net', 'b.example.org']);
      expect(parseProxyHosts(''), isEmpty);
    });

    test('headers on the resolve are themselves the signal', () {
      // Some CDN hostnames are generated per resolve, so no host list can
      // ever match them; the resolver attaching a Referer is what says the
      // upstream demands one.
      expect(
        needsSourceProxy(
          'https://a7b3c9.example.net/live.m3u8',
          headers: {'Referer': 'https://player.example/'},
        ),
        isTrue,
      );
    });
  });

  group('refererOf', () {
    test('finds the header whatever case it was spelled in', () {
      expect(refererOf({'referer': 'https://player.example/'}),
          'https://player.example/');
      expect(refererOf({'Referer': 'https://player.example/'}),
          'https://player.example/');
    });

    test('ignores anything that is not an http(s) URL', () {
      expect(refererOf({'Referer': 'player.example'}), '');
      expect(refererOf({'User-Agent': 'Mozilla/5.0'}), '');
      expect(refererOf(const {}), '');
    });
  });

  group('proxiedSourceUrl', () {
    test('carries the Referer through as ref=, ahead of url=', () {
      final url = proxiedSourceUrl(
        'https://cdn.example/master.m3u8',
        'https://host/streamio',
        headers: {'Referer': 'https://player.example/'},
      );
      expect(
        url,
        'https://host/streamio/api/cast-proxy?direct=1'
        '&ref=https%3A%2F%2Fplayer.example%2F'
        '&url=https%3A%2F%2Fcdn.example%2Fmaster.m3u8',
      );
    });

    test('omits ref= entirely when the resolver did not ask for one', () {
      final url = proxiedSourceUrl(
        'https://media.example.net/playlist/1',
        'https://host',
        pinnedHosts: _pinned,
      );
      expect(url, isNot(contains('ref=')));
      expect(url, startsWith('https://host/api/cast-proxy?direct=1&url='));
    });

    test('a source that needs no proxy is returned untouched', () {
      expect(
        proxiedSourceUrl('https://cdn.example/a.m3u8', 'https://host'),
        'https://cdn.example/a.m3u8',
      );
    });
  });
}
