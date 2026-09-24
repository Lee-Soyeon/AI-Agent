import 'package:ai_agent/browser/app_scheme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('웹 주소와 앱 호출 주소를 구분한다', () {
    for (final s in ['http', 'https', 'about', 'javascript', 'data', 'blob']) {
      expect(isWebScheme(s), isTrue, reason: s);
    }
    for (final s in ['ispmobile', 'kb-acp', 'intent', 'kftc-bankpay', 'hdcardappcardansimclick']) {
      expect(isWebScheme(s), isFalse, reason: s);
    }
  });

  test('안드로이드 intent 주소에서 앱 주소와 패키지를 꺼낸다', () {
    final r = parseIntentUrl(
      'intent://pay?tid=123&amt=19800#Intent;scheme=ispmobile;package=kvp.jjy.MispAndroid320;end',
    );
    expect(r.appUrl, 'ispmobile://pay?tid=123&amt=19800');
    expect(r.package, 'kvp.jjy.MispAndroid320');

    final noScheme = parseIntentUrl('intent://x#Intent;package=com.kbcard.cxh.appcard;end;');
    expect(noScheme.appUrl, isNull);
    expect(noScheme.package, 'com.kbcard.cxh.appcard');

    expect(parseIntentUrl('https://example.com').appUrl, isNull);
  });
}
