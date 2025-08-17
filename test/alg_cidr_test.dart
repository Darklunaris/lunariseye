import 'package:test/test.dart';
import 'package:lunariseye/scanner.dart' as sc;

void main() {
  test('expandCidr /30 yields 2 usable hosts', () {
    final hosts = sc.expandCidr('192.168.1.0/30');
    // /30 has 4 addresses, 2 usable hosts in many scanning contexts
    expect(hosts.length, equals(2));
    expect(hosts, contains('192.168.1.1'));
    expect(hosts, contains('192.168.1.2'));
  });
}
