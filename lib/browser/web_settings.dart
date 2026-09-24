import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 로그인용(보이는) 웹뷰와 에이전트용(헤드리스) 웹뷰가 같은 설정을 쓰도록 한 곳에 모은다.
///
/// 두 웹뷰는 플랫폼 기본 쿠키 저장소(Android CookieManager / iOS WKWebsiteDataStore.default)를
/// 공유하므로, 사용자가 보이는 웹뷰에서 로그인하면 백그라운드 웹뷰도 로그인 상태가 된다.
///
/// Google 은 "wv" 가 들어간 WebView 기본 User-Agent 로그인을 막기 때문에 일반 모바일 브라우저 UA 를 사용한다.
String get mobileUserAgent => Platform.isIOS
    ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1'
    : 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36';

InAppWebViewSettings buildWebSettings() => InAppWebViewSettings(
  userAgent: mobileUserAgent,
  javaScriptEnabled: true,
  domStorageEnabled: true,
  databaseEnabled: true,
  thirdPartyCookiesEnabled: true,
  sharedCookiesEnabled: true,
  // 새 창(target=_blank, window.open)을 같은 웹뷰에서 열어 에이전트가 놓치지 않도록 한다.
  supportMultipleWindows: false,
  // 결제창(안심결제·ISP)은 스크립트로 새 창을 연다. 막으면 결제 버튼이 반응하지 않는다.
  javaScriptCanOpenWindowsAutomatically: true,
  mediaPlaybackRequiresUserGesture: true,
  useShouldOverrideUrlLoading: false,
  isInspectable: true,
);
