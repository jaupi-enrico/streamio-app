import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/config/server_config.dart';

/// A Streamio install isn't always at the root of its origin — a common
/// reverse-proxy setup mounts it under a path, e.g.
/// `https://example.com/streamio`. Every URL the app builds has to keep
/// that prefix, so these pin the normalization down.
void main() {
  group('normalize', () {
    test('adds a scheme when one is omitted', () {
      expect(ServerConfig.normalize('streamio.example.com'),
          'https://streamio.example.com');
    });

    test('keeps a path prefix', () {
      expect(ServerConfig.normalize('streamio.example.com/streamio'),
          'https://streamio.example.com/streamio');
      expect(ServerConfig.normalize('https://streamio.example.com/streamio'),
          'https://streamio.example.com/streamio');
    });

    test('strips trailing slashes so path concatenation is safe', () {
      expect(ServerConfig.normalize('https://streamio.example.com/streamio/'),
          'https://streamio.example.com/streamio');
      expect(ServerConfig.normalize('https://streamio.example.com///'),
          'https://streamio.example.com');
    });

    test('never leaves a bare trailing "?" behind', () {
      // Uri.replace(query: '') produces one, and it would end up glued to
      // every path the app appends.
      for (final input in [
        'streamio.example.com',
        'streamio.example.com/streamio',
        'https://streamio.example.com/streamio?x=1',
      ]) {
        expect(ServerConfig.normalize(input), isNot(contains('?')),
            reason: 'input: $input');
      }
    });

    test('drops query and fragment', () {
      expect(
          ServerConfig.normalize('https://streamio.example.com/streamio?a=b#c'),
          'https://streamio.example.com/streamio');
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
      expect(ServerConfig.normalize('ftp://streamio.example.com'), isNull);
      expect(ServerConfig.normalize('http://'), isNull);
    });
  });

  group('endpoint construction', () {
    test('a path-prefixed base yields correct endpoints', () {
      final base = ServerConfig.normalize('streamio.example.com/streamio')!;

      // These are the concatenations used across the app: the Dio baseUrl,
      // ApiClient.absolute, the health probe, and the cast proxy.
      expect('$base/health', 'https://streamio.example.com/streamio/health');
      expect('$base/api/home', 'https://streamio.example.com/streamio/api/home');
      expect('$base/api/cast-proxy?direct=1&url=x',
          'https://streamio.example.com/streamio/api/cast-proxy?direct=1&url=x');
    });
  });

  group('candidate bases', () {
    test('walks up a pasted deep link', () {
      // Someone copying the address bar mid-browse pastes a page URL, not the
      // server root — so the probe has somewhere to fall back to.
      expect(
        ServerConfig.candidates('https://streamio.example.com/streamio/watch'),
        [
          'https://streamio.example.com/streamio/watch',
          'https://streamio.example.com/streamio',
          'https://streamio.example.com',
        ],
      );
    });

    test('a root URL has only itself', () {
      expect(ServerConfig.candidates('https://streamio.example.com'),
          ['https://streamio.example.com']);
    });
  });
}
