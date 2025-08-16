import 'package:test/test.dart';
import 'package:lunariseye/scanner.dart' as sc;

void main() {
  test('expandCidr /30 returns 2 hosts', () {
    final hosts = sc.expandCidr('192.168.1.0/30');
    expect(hosts.length, equals(2));
  });
}
