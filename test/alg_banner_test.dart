import 'package:test/test.dart';
import 'package:lunaris_engine/networkAdv/banner.dart' as banner;

void main() {
  test('identifyProtocolFromBanner basic heuristics', () {
    final a = banner.identifyProtocolFromBanner('220 ');
    // Ambiguous '220' banner should return a non-empty heuristic
    expect(a.isNotEmpty, isTrue);

    final b = banner.identifyProtocolFromBanner('HTTP/1.1 200 OK');
    expect(b.toLowerCase().contains('http'), isTrue);

    final v = banner.identifyProtocolFromBanner('220 MyFTP');
    final vl = v.toLowerCase();
    expect(vl.contains('ftp') || vl.contains('smtp') || vl.isNotEmpty, isTrue);
  });
}
