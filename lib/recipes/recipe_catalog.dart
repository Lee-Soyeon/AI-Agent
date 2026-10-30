import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 레시피 한 단계 (server/app/tasks.json 의 steps[]).
class RecipeStep {
  RecipeStep(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String;

  /// file | photo | text | chips | keyword
  String get kind => json['kind'] as String;
  String get text => json['text'] as String? ?? '';
  String? get why => json['why'] as String?;
  String? get button => json['button'] as String?;
  String? get placeholder => json['placeholder'] as String?;
  String? get accept => json['accept'] as String?;

  /// 앞 단계에서 뽑은 값으로 칩을 채울 때 (예: file.headers).
  String? get optionsFrom => json['options_from'] as String?;
  List<String> get options => [for (final o in (json['options'] as List? ?? const [])) '$o'];
  bool get allowFree => json['allow_free'] != false;

  /// 내용을 받는 단계인지 (파일·사진·긴 글).
  bool get isContent => kind == 'file' || kind == 'photo' || kind == 'text';
}

class Recipe {
  Recipe(this.json) : steps = [for (final s in (json['steps'] as List? ?? const [])) RecipeStep((s as Map).cast<String, dynamic>())] {
    assert(steps.length <= maxSteps, '레시피 $id 의 단계가 ${steps.length}개 (상한 $maxSteps)');
  }

  /// 홈에서 즉석으로 만든 레시피 (내 것부터 넣기 → 칩 선택).
  factory Recipe.synthetic({required String title, required String promptTemplate, String engine = 'llm'}) =>
      Recipe({
        'id': 'synthetic_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        'title': title,
        'can': '',
        'cannot': '',
        'personas': const <String>[],
        'inputs': const <String>[],
        'engine': engine,
        'steps': const <Map<String, dynamic>>[],
        'prompt_template': promptTemplate,
        'next': null,
      });

  static const maxSteps = 3;

  final Map<String, dynamic> json;
  final List<RecipeStep> steps;

  String get id => json['id'] as String;
  String get title => json['title'] as String;
  String get can => json['can'] as String? ?? '';
  String get cannot => json['cannot'] as String? ?? '';
  List<String> get personas => [for (final p in (json['personas'] as List? ?? const [])) '$p'];
  List<String> get inputs => [for (final i in (json['inputs'] as List? ?? const [])) '$i'];

  /// llm | browser | gmail
  String get engine => json['engine'] as String? ?? 'llm';
  String get promptTemplate => json['prompt_template'] as String? ?? '';
  String? get next => json['next'] as String?;
  Map<String, dynamic>? get gallery => (json['gallery'] as Map?)?.cast<String, dynamic>();
  String get galleryLine => gallery?['line'] as String? ?? can;
  String? get galleryBefore => gallery?['before'] as String?;
  String? get galleryAfter => gallery?['after'] as String?;
  bool get isSynthetic => id.startsWith('synthetic_');
}

class RecipePersona {
  const RecipePersona(this.id, this.label);
  final String id;
  final String label;
}

/// 레시피 카탈로그. 앱(asset)과 서버가 같은 파일을 쓴다.
class RecipeCatalog {
  RecipeCatalog._(this.recipes, this.personas, this._routines, this._intakeDefaults) {
    for (final r in recipes) {
      if (r.steps.length > Recipe.maxSteps) {
        throw StateError('레시피 ${r.id} 의 단계가 ${r.steps.length}개 (상한 ${Recipe.maxSteps})');
      }
    }
  }

  factory RecipeCatalog.fromJson(String source) {
    final j = (jsonDecode(source) as Map).cast<String, dynamic>();
    return RecipeCatalog._(
      [for (final r in j['recipes'] as List) Recipe((r as Map).cast<String, dynamic>())],
      [for (final p in (j['personas'] as List? ?? const [])) RecipePersona('${p['id']}', '${p['label']}')],
      {
        for (final e in ((j['routines'] as Map?) ?? const {}).entries)
          '${e.key}': [for (final v in e.value as List) '$v'],
      },
      {
        for (final e in ((j['intake_defaults'] as Map?) ?? const {}).entries)
          '${e.key}': [for (final v in e.value as List) '$v'],
      },
    );
  }

  static const assetPath = 'server/app/tasks.json';

  static Future<RecipeCatalog> load() async => RecipeCatalog.fromJson(await rootBundle.loadString(assetPath));

  /// 빈 카탈로그 (로드 실패 시 앱이 멈추지 않게).
  static RecipeCatalog empty() => RecipeCatalog._(const [], const [], const {}, const {});

  final List<Recipe> recipes;
  final List<RecipePersona> personas;
  final Map<String, List<String>> _routines;
  final Map<String, List<String>> _intakeDefaults;

  List<String> routinesFor(String persona) => _routines[persona] ?? _routines['other'] ?? const ['없음'];

  /// 서버 /intake 가 늦거나 실패했을 때 쓸 기본 칩 (photo | file | text).
  List<String> intakeDefaults(String kind) => _intakeDefaults[kind] ?? const ['쉽게 풀기', '고치기', '요약'];

  Recipe? byId(String id) => recipes.where((r) => r.id == id).firstOrNull;

  /// 제목이 정확히 같은 레시피.
  Recipe? find(String title) => recipes.where((r) => r.title.trim() == title.trim()).firstOrNull;

  /// 내 직업에 맞는 것만. 반복하는 일([routine])과 이름이 겹치는 것이 맨 앞. 직업을 안 골랐으면 전부.
  List<Recipe> forPersona(String? persona, {String? routine}) {
    if (persona == null || persona.isEmpty) return List.of(recipes);
    final mine = recipes.where((r) => r.personas.contains(persona)).toList();
    final word = (routine ?? '').trim().split(RegExp(r'\s+')).first;
    if (word.length < 2 || word == '없음') return mine;
    bool hit(Recipe r) => r.title.contains(word) || r.galleryLine.contains(word);
    return [...mine.where(hit), ...mine.where((r) => !hit(r))];
  }

  /// 내 직업에 안 맞는 나머지 (원래 순서).
  List<Recipe> othersFor(String? persona) {
    if (persona == null || persona.isEmpty) return const [];
    return recipes.where((r) => !r.personas.contains(persona)).toList();
  }

  /// 오늘의 하나: 반복하는 일과 맞는 것이 있으면 그것, 없으면 내 것 중에서 날짜로 순환.
  Recipe? todays([DateTime? now, String? persona, String? routine]) {
    final pool = forPersona(persona, routine: routine);
    if (pool.isEmpty) return null;
    final word = (routine ?? '').trim().split(RegExp(r'\s+')).first;
    if (word.length >= 2 && word != '없음' && (pool.first.title.contains(word) || pool.first.galleryLine.contains(word))) {
      return pool.first;
    }
    final d = now ?? DateTime.now();
    final doy = d.difference(DateTime(d.year, 1, 1)).inDays;
    return pool[doy % pool.length];
  }

  /// 입력 종류(photo | file | text)로 할 수 있는 레시피.
  List<Recipe> forInput(String kind) => recipes.where((r) => r.inputs.contains(kind)).toList();
}
