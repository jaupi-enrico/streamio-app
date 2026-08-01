import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/config/server_config.dart';

/// A Streamio install isn't always at the root of its origin — a common
/// reverse-proxy setup mounts it under a path, e.g.
/// `https://streamio.ddns.net/streamio`. Every URL the app builds has to keep
/// that prefix, so these pin the normalization down.
void main() {
  group('normalize', () {
    test('adds a scheme when one is omitted', () {
      expect(ServerConfig.normalize('streamio.ddns.net'),
          'https://streamio.ddns.net');
    });

    test('keeps a path prefix', () {
      expect(ServerConfig.normalize('streamio.ddns.net/streamio'),
          'https://streamio.ddns.net/streamio');
      expect(ServerConfig.normalize('https://streamio.ddns.net/streamio'),
          'https://streamio.ddns.net/streamio');
    });

    test('strips trailing slashes so path concatenation is safe', () {
      expect(ServerConfig.normalize('https://streamio.ddns.net/streamio/'),
          'https://streamio.ddns.net/streamio');
      expect(ServerConfig.normalize('https://streamio.ddns.net///'),
          'https://streamio.ddns.net');
    });

    test('never leaves a bare trailing "?" behind', () {
      // Uri.replace(query: '') produces one, and it would end up glued to
      // every path the app appends.
      for (final input in [
        'streamio.ddns.net',
        'streamio.ddns.net/streamio',
        'https://streamio.ddns.net/streamio?x=1',
      ]) {
        expect(ServerConfig.normalize(input), isNot(contains('?')),
            reason: 'input: $input');
      }
    });

    test('drops query and fragment', () {
      expect(ServerConfig.normalize('https://streamio.ddns.net/streamio?a=b#c'),
          'https://streamio.ddns.net/streamio');
    });

    test('keeps an explicit port', () {
      expect(ServerConfig.normalize('192.168.1.10:3003'),
          'https://192.168.1.10:3003');
      expect(ServerConfig.normalize('http://192.168.1.10:3003/streamio'),
          'http://192.168.1.10:3003/streamio');
    });

    test('preserves http, so a LAN address is not forced to https', () {
      expect(ServerConfig.normalize('http://streamio.local'),
          'http://streamio.local');
    });

    test('rejects unusable input', () {
      expect(ServerConfig.normalize(''), isNull);
      expect(ServerConfig.normalize('   '), isNull);
      expect(ServerConfig.normalize('ftp://streamio.ddns.net'), isNull);
      expect(ServerConfig.normalize('http://'), isNull);
    });
  });

  group('endpoint construction', () {
    test('a path-prefixed base yields correct endpoints', () {
      final base = ServerConfig.normalize('streamio.ddns.net/streamio')!;

      // These are the concatenations used across the app: the Dio baseUrl,
      // ApiClient.absolute, the health probe, and the cast proxy.
      expect('$base/health', 'https://streamio.ddns.net/streamio/health');
      expect('$base/api/home', 'https://streamio.ddns.net/streamio/api/home');
      expect('$base/api/cast-proxy?direct=1&url=x',
          'https://streamio.ddns.net/streamio/api/cast-proxy?direct=1&url=x');
    });
  });

  group('candidate bases', () {
    test('walks up a pasted deep link', () {
      // Someone copying the address bar mid-browse pastes a page URL, not the
      // server root — so the probe has somewhere to fall back to.
      expect(
        ServerConfig.candidates('https://streamio.ddns.net/streamio/watch'),
        [
          'https://streamio.ddns.net/streamio/watch',
          'https://streamio.ddns.net/streamio',
          'https://streamio.ddns.net',
        ],
      );
    });

    test('a root URL has only itself', () {
      expect(ServerConfig.candidates('https://streamio.ddns.net'),
          ['https://streamio.ddns.net']);
    });
  });
}
