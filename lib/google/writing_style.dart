import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../llm/llm_types.dart';
import 'gmail_api.dart';

/// 보낸 메일 한 통 (인용문을 걷어낸 사용자 본인의 글).
class SentEmailSample {
  const SentEmailSample({
    required this.to,
    required this.subject,
    required this.date,
    required this.body,
  });

  final String to;
  final String subject;
  final String date;
  final String body;

  String toPrompt(int index) =>
      ['### 예시 ${index + 1}', '받는 사람: $to', '제목: $subject', '날짜: $date', '본문:', body].join('\n');
}

/// 학습된 말투 프로필.
class StyleProfile {
  const StyleProfile({required this.guide, required this.analyzedCount, required this.updatedAt});

  factory StyleProfile.fromJson(Map<String, dynamic> j) => StyleProfile(
    guide: j['guide'] as String,
    analyzedCount: j['analyzedCount'] as int? ?? 0,
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  /// LLM 이 정리한 말투·형식 가이드 (사용자가 직접 고칠 수 있다).
  final String guide;
  final int analyzedCount;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'guide': guide,
    'analyzedCount': analyzedCount,
    'updatedAt': updatedAt.toIso8601String(),
  };

  StyleProfile copyWith({String? guide}) =>
      StyleProfile(guide: guide ?? this.guide, analyzedCount: analyzedCount, updatedAt: updatedAt);
}

/// 보낸 메일에서 인용된 이전 메일(답장 원문)을 잘라내 사용자가 직접 쓴 부분만 남긴다.
String cleanSentBody(String body, {int maxChars = 1200}) {
  final quoteStart = [
    RegExp(r'^On .+wrote:\s*$', caseSensitive: false),
    RegExp(r'님이 작성(했습니다)?:\s*$'),
    RegExp(
      r'^-{2,}\s*(Original Message|원본 메시지|Forwarded message|전달된 메시지)\s*-{2,}',
      caseSensitive: false,
    ),
    RegExp(r'^(From|보낸 사람|보낸사람)\s*:', caseSensitive: false),
  ];
  final kept = <String>[];
  for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
    final t = line.trim();
    if (quoteStart.any((re) => re.hasMatch(t))) break;
    if (t.startsWith('>')) continue;
    kept.add(line.trimRight());
  }
  var text = kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (text.length > maxChars) text = '${text.substring(0, maxChars)}…';
  return text;
}

/// 보낸 메일함에서 예시를 가져온다. [query] 로 받는 사람 등을 좁힐 수 있다 (예: `to:kim@a.com`).
Future<List<SentEmailSample>> fetchSentSamples(
  GmailApi gmail, {
  int max = 50,
  String query = '',
  int maxChars = 1200,
}) async {
  final ids = await gmail.searchIds('in:sent $query'.trim(), max: max);
  final messages = await gmail.readMany(ids);
  return [
    for (final m in messages)
      if (cleanSentBody(m.body, maxChars: maxChars) case final body when body.length >= 10)
        SentEmailSample(
          to: m.header('to'),
          subject: m.header('subject'),
          date: m.header('date'),
          body: body,
        ),
  ];
}

const styleAnalysisSystemPrompt = '''
당신은 글쓰기 문체 분석가입니다. 사용자가 실제로 보낸 이메일들을 읽고,
다른 AI 가 이 사용자와 **구별할 수 없을 만큼 똑같이** 메일을 쓸 수 있도록 말투·형식 가이드를 한국어로 작성합니다.''';

String buildStyleAnalysisPrompt(List<SentEmailSample> samples) =>
    '''
아래는 사용자가 직접 보낸 이메일 ${samples.length}통입니다 (인용된 상대방 메일은 제거됨).

다음 항목별로 구체적인 규칙과 **실제 문구 예시**를 담아 가이드를 작성하세요. 추측하지 말고 예시에서 확인되는 것만 쓰세요.
1. 인사말 (첫 줄 패턴, 상대 호칭 방식 — 예: "OO님", "OO 대표님", "Hi OO")
2. 자기소개/첫 문장 패턴
3. 존댓말 수준과 어미 (예: "~습니다" vs "~요", 문장 끝 습관)
4. 문장 길이, 문단 나누기, 목록/번호 사용 여부
5. 자주 쓰는 표현·접속어·맺음 표현
6. 맺음말과 **서명 (있는 그대로 정확히 복사)**
7. 상대에 따른 차이 (사내/외부/고객/지인, 한국어/영어 메일)
8. 제목(Subject) 작성 방식
9. 하지 않는 것 (예: 이모지 안 씀, 느낌표 거의 안 씀)

마지막에 "## 대표 예시" 로, 가장 전형적인 메일 1~2통을 개인정보(전화번호·계좌 등)를 가린 채 그대로 옮겨 적으세요.

${[for (var i = 0; i < samples.length; i++) samples[i].toPrompt(i)].join('\n\n')}
''';

/// 말투 프로필 저장소. 가이드에는 서명·메일 일부가 들어가므로 보안 저장소에 둔다.
abstract class StyleProfileStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureStyleProfileStore implements StyleProfileStore {
  static const _key = 'writing_style_profile';
  final _secure = const FlutterSecureStorage();

  @override
  Future<String?> read() => _secure.read(key: _key);
  @override
  Future<void> write(String value) => _secure.write(key: _key, value: value);
  @override
  Future<void> delete() => _secure.delete(key: _key);
}

class MemoryStyleProfileStore implements StyleProfileStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

class WritingStyleStore extends ChangeNotifier {
  WritingStyleStore({StyleProfileStore? store}) : _store = store ?? SecureStyleProfileStore();

  final StyleProfileStore _store;

  StyleProfile? profile;
  bool busy = false;
  String? progress;
  String? error;

  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw != null) profile = StyleProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      profile = null;
    }
    notifyListeners();
  }

  /// 보낸 메일 [sampleSize] 통을 LLM 으로 분석해 말투 가이드를 만든다.
  Future<void> learn({
    required LlmProvider llm,
    required GmailApi gmail,
    int sampleSize = 50,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    progress = '보낸 메일을 불러오는 중…';
    notifyListeners();
    try {
      final samples = await fetchSentSamples(gmail, max: sampleSize);
      if (samples.length < 3) {
        throw StateError('분석할 보낸 메일이 부족합니다 (${samples.length}통). 메일을 몇 통 더 보낸 뒤 다시 시도하세요.');
      }
      progress = '${samples.length}통의 말투를 분석하는 중…';
      notifyListeners();
      final res = await llm.complete(
        system: styleAnalysisSystemPrompt,
        messages: [ChatMessage.user(buildStyleAnalysisPrompt(samples))],
        tools: const [],
      );
      final guide = res.text?.trim() ?? '';
      if (guide.isEmpty) throw StateError('LLM 이 빈 가이드를 돌려주었습니다.');
      await _save(
        StyleProfile(guide: guide, analyzedCount: samples.length, updatedAt: DateTime.now()),
      );
    } catch (e) {
      error = '말투 학습 실패: $e';
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  /// 사용자가 가이드를 직접 고쳤을 때.
  Future<void> updateGuide(String guide) async {
    final p = profile;
    if (p == null) return;
    await _save(p.copyWith(guide: guide.trim()));
  }

  Future<void> clear() async {
    profile = null;
    await _store.delete();
    notifyListeners();
  }

  Future<void> _save(StyleProfile p) async {
    profile = p;
    await _store.write(jsonEncode(p.toJson()));
    notifyListeners();
  }
}
