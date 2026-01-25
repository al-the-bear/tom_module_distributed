import 'package:test/test.dart';

// Test the pattern matching logic used in RemoteApiServer._matchesTrustedHostPattern
// This is the same algorithm, extracted for testing

/// Matches a client IP or hostname against a trusted host pattern.
bool matchesTrustedHostPattern(String clientIp, String pattern) {
  // Exact match
  if (clientIp == pattern) return true;

  // Check if pattern contains wildcard
  if (!pattern.contains('*')) return false;

  // Convert pattern to regex
  // Escape special regex chars except *, then convert * to regex pattern
  final escaped = pattern.replaceAll('.', r'\.').replaceAll('*', '[^.]*');

  final regex = RegExp('^$escaped\$');
  return regex.hasMatch(clientIp);
}

void main() {
  group('Trusted Host Pattern Matching', () {
    group('exact match', () {
      test('matches exact IP', () {
        expect(
          matchesTrustedHostPattern('192.168.1.100', '192.168.1.100'),
          isTrue,
        );
        expect(matchesTrustedHostPattern('10.0.0.1', '10.0.0.1'), isTrue);
      });

      test('matches localhost variations', () {
        expect(matchesTrustedHostPattern('localhost', 'localhost'), isTrue);
        expect(matchesTrustedHostPattern('127.0.0.1', '127.0.0.1'), isTrue);
        expect(matchesTrustedHostPattern('::1', '::1'), isTrue);
      });

      test('rejects non-matching exact', () {
        expect(
          matchesTrustedHostPattern('192.168.1.100', '192.168.1.101'),
          isFalse,
        );
        expect(matchesTrustedHostPattern('10.0.0.1', '10.0.0.2'), isFalse);
      });
    });

    group('IP wildcard patterns', () {
      test('matches single octet wildcard', () {
        expect(matchesTrustedHostPattern('192.168.1.0', '192.168.1.*'), isTrue);
        expect(
          matchesTrustedHostPattern('192.168.1.100', '192.168.1.*'),
          isTrue,
        );
        expect(
          matchesTrustedHostPattern('192.168.1.255', '192.168.1.*'),
          isTrue,
        );
      });

      test('rejects non-matching single octet wildcard', () {
        expect(
          matchesTrustedHostPattern('192.168.2.100', '192.168.1.*'),
          isFalse,
        );
        expect(matchesTrustedHostPattern('10.0.0.1', '192.168.1.*'), isFalse);
      });

      test('matches multiple octet wildcards', () {
        expect(matchesTrustedHostPattern('10.0.0.1', '10.0.*.*'), isTrue);
        expect(matchesTrustedHostPattern('10.0.255.255', '10.0.*.*'), isTrue);
        expect(matchesTrustedHostPattern('10.0.1.100', '10.0.*.*'), isTrue);
      });

      test('rejects non-matching multiple octet wildcards', () {
        expect(matchesTrustedHostPattern('10.1.0.1', '10.0.*.*'), isFalse);
        expect(matchesTrustedHostPattern('192.168.1.1', '10.0.*.*'), isFalse);
      });

      test('matches leading wildcard', () {
        expect(matchesTrustedHostPattern('1.0.0.1', '*.0.0.1'), isTrue);
        expect(matchesTrustedHostPattern('255.0.0.1', '*.0.0.1'), isTrue);
      });
    });

    group('hostname wildcard patterns', () {
      test('matches subdomain wildcard', () {
        expect(
          matchesTrustedHostPattern('api.mydomain.com', '*.mydomain.com'),
          isTrue,
        );
        expect(
          matchesTrustedHostPattern('www.mydomain.com', '*.mydomain.com'),
          isTrue,
        );
        expect(
          matchesTrustedHostPattern('internal.mydomain.com', '*.mydomain.com'),
          isTrue,
        );
      });

      test('does not match deep subdomains with single wildcard', () {
        // *.mydomain.com should NOT match api.internal.mydomain.com
        // because * only matches chars except dots
        expect(
          matchesTrustedHostPattern(
            'api.internal.mydomain.com',
            '*.mydomain.com',
          ),
          isFalse,
        );
      });

      test('matches hostname prefix wildcard', () {
        expect(
          matchesTrustedHostPattern('server-1.local', 'server-*.local'),
          isTrue,
        );
        expect(
          matchesTrustedHostPattern('server-2.local', 'server-*.local'),
          isTrue,
        );
        expect(
          matchesTrustedHostPattern('server-100.local', 'server-*.local'),
          isTrue,
        );
      });

      test('rejects non-matching hostname patterns', () {
        expect(
          matchesTrustedHostPattern('api.otherdomain.com', '*.mydomain.com'),
          isFalse,
        );
        expect(
          matchesTrustedHostPattern('client-1.local', 'server-*.local'),
          isFalse,
        );
      });
    });

    group('edge cases', () {
      test('empty strings', () {
        expect(matchesTrustedHostPattern('', ''), isTrue);
        expect(matchesTrustedHostPattern('192.168.1.1', ''), isFalse);
        expect(matchesTrustedHostPattern('', '192.168.1.1'), isFalse);
      });

      test('special characters in pattern', () {
        // Dots should be escaped properly
        expect(
          matchesTrustedHostPattern('192x168x1x1', '192.168.1.1'),
          isFalse,
        );
      });

      test('IPv6 addresses', () {
        expect(matchesTrustedHostPattern('::1', '::1'), isTrue);
        expect(matchesTrustedHostPattern('fe80::1', 'fe80::1'), isTrue);
      });

      test('wildcard only', () {
        // Single * should match any single "segment"
        expect(matchesTrustedHostPattern('localhost', '*'), isTrue);
        expect(matchesTrustedHostPattern('192', '*'), isTrue);
        // But not something with dots (since * doesn't match dots)
        expect(matchesTrustedHostPattern('192.168.1.1', '*'), isFalse);
      });
    });
  });
}
