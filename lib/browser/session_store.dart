import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sites.dart';

/// 사이트별 로그인 여부(사용자가 로그인 창에서 로그인을 끝냈는지)를 기억한다.
/// 실제 인증 정보는 웹뷰 쿠키 저장소에만 있고 앱은 비밀번호를 절대 보관하지 않는다.
class SiteSessionStore extends ChangeNotifier {
  final Map<String, DateTime> _loggedInAt = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final s in allSites) {
      final ms = prefs.getInt('login_${s.id}');
      if (ms != null) _loggedInAt[s.id] = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    notifyListeners();
  }

  bool isLoggedIn(SiteConfig site) => _loggedInAt.containsKey(site.id);
  DateTime? loggedInAt(SiteConfig site) => _loggedInAt[site.id];

  Future<void> markLoggedIn(SiteConfig site) async {
    final now = DateTime.now();
    _loggedInAt[site.id] = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('login_${site.id}', now.millisecondsSinceEpoch);
    notifyListeners();
  }

  Future<void> logout(SiteConfig site) async {
    final cm = CookieManager.instance();
    for (final d in site.cookieDomains) {
      final host = d.startsWith('.') ? d.substring(1) : d;
      try {
        await cm.deleteCookies(url: WebUri('https://$host/'), domain: d);
        await cm.deleteCookies(url: WebUri('https://$host/'));
      } catch (_) {}
    }
    _loggedInAt.remove(site.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('login_${site.id}');
    notifyListeners();
  }
}
