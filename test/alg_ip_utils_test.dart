import 'package:test/test.dart';
import 'package:lunariseye/scanner.dart' as sc;

void main() {
  test('isPrivateIp recognizes common private and public ranges', () {
    expect(sc.isPrivateIp('127.0.0.1'), isTrue);
    expect(sc.isPrivateIp('10.0.0.5'), isTrue);
    expect(sc.isPrivateIp('172.16.0.1'), isTrue);
    expect(sc.isPrivateIp('172.31.255.255'), isTrue);
    expect(sc.isPrivateIp('192.168.1.1'), isTrue);
    expect(sc.isPrivateIp('8.8.8.8'), isFalse);
    expect(sc.isPrivateIp('1.2.3.4'), isFalse);
  });
}
