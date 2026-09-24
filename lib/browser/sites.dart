import 'package:flutter/material.dart';

/// 에이전트가 다룰 수 있는 사이트 정의. 새 사이트는 여기에 추가하면 된다.
class SiteConfig {
  const SiteConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.loginUrl,
    required this.homeUrl,
    required this.loggedInUrlPattern,
    required this.cookieDomains,
    required this.agentHints,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;

  /// 사용자가 직접 로그인할 페이지.
  final String loginUrl;

  /// 에이전트가 작업을 시작할 페이지.
  final String homeUrl;

  /// 이 정규식에 맞는 URL 로 이동하면 로그인이 끝났다고 보고 로그인 창을 자동으로 닫는다.
  final String loggedInUrlPattern;

  bool isLoggedInUrl(String url) => RegExp(loggedInUrlPattern).hasMatch(url);

  /// 로그아웃 시 쿠키를 지울 도메인.
  final List<String> cookieDomains;

  /// 시스템 프롬프트에 들어갈 사이트별 팁.
  final String agentHints;
}

const coupang = SiteConfig(
  id: 'coupang',
  name: '쿠팡',
  icon: Icons.shopping_cart,
  color: Color(0xFFE52528),
  loginUrl: 'https://login.coupang.com/login/login.pang?rtnUrl=https%3A%2F%2Fm.coupang.com%2F',
  homeUrl: 'https://m.coupang.com/',
  loggedInUrlPattern: r'^https://(m|www)\.coupang\.com/',
  cookieDomains: ['.coupang.com', 'coupang.com', 'login.coupang.com', 'm.coupang.com'],
  agentHints: '''- 모바일 웹 홈: https://m.coupang.com/
- 검색: https://m.coupang.com/nm/search?q=<검색어(URL 인코딩)>
- 장바구니: https://cart.coupang.com/cartView.pang
- 상품 선택 시 가격, 단위가격, 로켓배송 여부, 리뷰 수/평점을 비교해 사용자의 의도에 가장 맞는 상품을 고르세요.
- '장바구니 담기'는 승인 없이 해도 됩니다.
- 주문서에서 결제수단은 **쿠페이(등록된 카드·계좌)**를 고르세요. '신용/체크카드'(카드번호 새로 입력)는 고르지 마세요.
- 주문서가 준비되면 '결제하기'를 누르지 말고 handoff_payment 로 사용자에게 넘기세요 (결제 비밀번호는 사용자가 입력).''',
);

/// 웹 자동화(인앱 브라우저 로그인 + 헤드리스 웹뷰)로 다루는 사이트.
/// Gmail 은 웹 자동화 대신 Google 로그인 + Gmail API 를 쓴다 (lib/google/).
const allSites = [coupang];

SiteConfig? siteById(String id) {
  for (final s in allSites) {
    if (s.id == id) return s;
  }
  return null;
}
