import 'package:test/test.dart';
import 'package:lunaris_engine/networkAdv/timeout.dart' as t;

void main() {
  test('EWMA update and adaptive timeout trend', () {
    final host = '1.2.3.4';
    // initial base timeout
    final base = Duration(milliseconds: 300);
    // Without any samples, adaptiveTimeout should return base
    expect(t.adaptiveTimeoutForHost(host, base), equals(base));

    // Feed increasing RTT samples and ensure adaptiveTimeout grows
    t.updateRtt(host, 100);
    final t1 = t.adaptiveTimeoutForHost(host, base);
    expect(t1.inMilliseconds >= base.inMilliseconds, isTrue);

    // More samples should adjust the EWMA
    t.updateRtt(host, 200);
    final t2 = t.adaptiveTimeoutForHost(host, base);
    expect(t2.inMilliseconds >= t1.inMilliseconds, isTrue);
  });
}
