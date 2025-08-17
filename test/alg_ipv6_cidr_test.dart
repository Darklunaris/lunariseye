import 'package:test/test.dart';
import 'package:lunariseye/scanner.dart' as sc;

void main() {
  test('expandCidr IPv6 /128 loopback returns ::1', () {
    final hosts = sc.expandCidr('::1/128');
    expect(hosts.length, equals(1));
    expect(hosts.first, equals('::1'));
  });

  test('expandCidr IPv6 /127 returns two addresses', () {
    final hosts = sc.expandCidr('2001:db8::/127');
    expect(hosts.length, equals(2));
  });
}
