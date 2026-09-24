import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 한국에서 많이 쓰는 서비스 한 개 (server/app/services.json).
class KService {
  KService(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get name => json['name'] as String;
  String get category => json['category'] as String;

  /// web | partial | app_only | excluded
  String get web => json['web'] as String;
  String? get home => json['home'] as String?;
  String? get login => json['login'] as String?;
  String? get search => json['search'] as String?;
  String? get hint => json['hint'] as String?;
  String? get note => json['note'] as String?;
  String? get account => json['account'] as String?;

  bool get supported => web == 'web' || web == 'partial';

  String? searchUrl(String keyword) => search?.replaceAll('{q}', Uri.encodeComponent(keyword));

  String describe() {
    final b = StringBuffer('### $name ($category)\n');
    if (!supported) {
      b.write('- 브라우저로는 지원하지 않음: ${note ?? '앱 전용'}. 사용자에게 그렇게 알리세요.');
      return b.toString();
    }
    b.writeln('- 시작: $home');
    if (login != null) b.writeln('- 로그인: $login${account != null ? ' ($account 계정 공유)' : ''}');
    if (search != null) b.writeln('- 검색 URL: $search  ({q} 에 URL 인코딩한 검색어)');
    if (hint != null) b.writeln('- 팁: $hint');
    if (web == 'partial') b.writeln('- 제한: ${note ?? '웹 기능 일부만 가능'}');
    return b.toString().trimRight();
  }
}

class ServiceCatalog {
  ServiceCatalog(this.services);

  factory ServiceCatalog.fromJson(String source) => ServiceCatalog([
    for (final s in (jsonDecode(source) as Map)['services'] as List)
      KService((s as Map).cast<String, dynamic>()),
  ]);

  static const assetPath = 'server/app/services.json';

  static Future<ServiceCatalog> load() async =>
      ServiceCatalog.fromJson(await rootBundle.loadString(assetPath));

  final List<KService> services;

  List<KService> get supported => services.where((s) => s.supported).toList();

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  List<KService> find(String query) {
    final q = _norm(query);
    if (q.isEmpty) return const [];
    final exact = services.where((s) => _norm(s.id) == q || _norm(s.name) == q).toList();
    if (exact.isNotEmpty) return exact;
    return services
        .where(
          (s) =>
              _norm(s.name).contains(q) || _norm(s.id).contains(q) || _norm(s.category).contains(q),
        )
        .take(5)
        .toList();
  }

  /// 시스템 프롬프트용 짧은 목록 (이름만). 상세는 service_info 도구로.
  String promptIndex() =>
      '- 브라우저로 지원: ${supported.map((s) => s.name).join(', ')}\n'
      '- 지원 안 함(앱 전용·보안상 제외): '
      '${services.where((s) => !s.supported).map((s) => s.name).join(', ')}';

  Map<String, List<KService>> byCategory() {
    final m = <String, List<KService>>{};
    for (final s in services) {
      (m[s.category] ??= []).add(s);
    }
    return m;
  }
}
