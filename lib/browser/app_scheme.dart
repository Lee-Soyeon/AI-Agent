import 'package:url_launcher/url_launcher.dart';

/// 결제창이 카드사·은행 앱을 부를 때 쓰는 주소(ispmobile://, kb-acp://, intent://…)를 처리한다.
/// 웹뷰는 이런 주소를 열 수 없으므로 앱을 직접 실행해 줘야 결제가 이어진다.
bool isWebScheme(String scheme) => const {
  'http',
  'https',
  'about',
  'data',
  'javascript',
  'blob',
  'file',
}.contains(scheme.toLowerCase());

/// 안드로이드 intent URL → (실행할 앱 주소, 앱이 없을 때 설치할 패키지).
/// 예: intent://pay?x=1#Intent;scheme=ispmobile;package=kvp.jjy.MispAndroid320;end
({String? appUrl, String? package}) parseIntentUrl(String url) {
  final m = RegExp(r'^intent://([^#]*)#Intent;(.*)end;?$').firstMatch(url);
  if (m == null) return (appUrl: null, package: null);
  final params = <String, String>{};
  for (final p in m.group(2)!.split(';')) {
    final i = p.indexOf('=');
    if (i > 0) params[p.substring(0, i)] = p.substring(i + 1);
  }
  final scheme = params['scheme'];
  return (appUrl: scheme == null ? null : '$scheme://${m.group(1)}', package: params['package']);
}

/// 앱 주소를 실행한다. 실패하면 false (앱 미설치 등).
Future<bool> launchAppUrl(String url) async {
  Future<bool> open(String u) async {
    try {
      return await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  if (url.startsWith('intent:')) {
    final (:appUrl, :package) = parseIntentUrl(url);
    if (appUrl != null && await open(appUrl)) return true;
    if (package != null) return open('market://details?id=$package');
    return false;
  }
  return open(url);
}
