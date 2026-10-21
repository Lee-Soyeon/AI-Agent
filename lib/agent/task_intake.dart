import '../recipes/recipe_catalog.dart';
import 'intake_content.dart';

/// 레시피 → 단계 화면(최대 3) → 문장 조립 → 확인. (PRD 4.1, 5.3)
///
/// 채팅이 아니다. 각 단계는 화면 하나이고, 답은 칩 또는 키워드다.
/// 내용 단계(file·photo·text)는 [IntakeContent] 로 받고, 그 외는 문자열로 받는다.
class TaskIntake {
  TaskIntake(this.recipe, {IntakeContent? content}) {
    if (recipe.steps.length > Recipe.maxSteps) {
      throw StateError('단계는 ${Recipe.maxSteps}개까지: ${recipe.id}');
    }
    // 홈에서 이미 내용을 넣고 들어왔으면 첫 내용 단계는 건너뛴다.
    if (content != null) {
      this.content = content;
      final first = recipe.steps.indexWhere((s) => s.isContent);
      if (first >= 0) {
        answers[recipe.steps[first].id] = content.asPromptText();
        _skipped.add(first);
      }
    }
    _index = _nextIndex(-1);
  }

  final Recipe recipe;
  final Map<String, String> answers = {};
  IntakeContent? content;
  final Set<int> _skipped = {};
  int _index = 0;

  int get index => _index;
  int get total => recipe.steps.length - _skipped.length;

  /// 지금까지 답한 단계 수 (진행 점용).
  int get position => recipe.steps.take(_index).where((s) => !_skipped.contains(recipe.steps.indexOf(s))).length;

  bool get isDone => _index >= recipe.steps.length;
  RecipeStep? get step => isDone ? null : recipe.steps[_index];

  int _nextIndex(int from) {
    var i = from + 1;
    while (i < recipe.steps.length && _skipped.contains(i)) {
      i++;
    }
    return i;
  }

  /// 현재 단계의 칩. options_from 이 있으면 받은 내용에서 뽑는다.
  List<String> optionsFor(RecipeStep s) {
    final from = s.optionsFrom;
    if (from == null) return s.options;
    if (from == 'file.headers' || from == 'photo.headers') {
      final h = content?.headers ?? const [];
      if (h.isNotEmpty) return h.take(6).toList();
    }
    return s.options.isEmpty ? const ['직접 고를게요'] : s.options;
  }

  /// 현재 단계에 답하고 다음으로.
  void answer(String value) {
    final s = step;
    if (s == null) return;
    answers[s.id] = value.trim();
    _index = _nextIndex(_index);
  }

  /// 내용 단계에 파일·사진·글을 넣는다.
  void answerContent(IntakeContent c) {
    final s = step;
    if (s == null) return;
    content = c;
    answers[s.id] = c.asPromptText();
    _index = _nextIndex(_index);
  }

  /// 한 단계 뒤로. 더 못 가면 false.
  bool back() {
    var i = _index - 1;
    while (i >= 0 && _skipped.contains(i)) {
      i--;
    }
    if (i < 0) return false;
    _index = i;
    answers.remove(recipe.steps[i].id);
    return true;
  }

  /// 지금까지 조립된 문장 (상단 보조 줄용). 아직 안 채운 자리는 비운다.
  String get assembled => substitute(recipe.promptTemplate, answers, content, keepMissing: false);

  /// 확인 화면에 보여줄 최종 문장.
  String get sentence => substitute(recipe.promptTemplate, answers, content);

  /// {id} 자리를 답으로 바꾼다. {file}/{photo}/{text}/{content} 는 받은 내용으로.
  static String substitute(
    String template,
    Map<String, String> answers,
    IntakeContent? content, {
    bool keepMissing = true,
  }) {
    final text = content?.asPromptText() ?? '';
    return template.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_]+)\}'), (m) {
      final k = m[1]!;
      if (answers.containsKey(k)) return answers[k]!;
      if (k == 'file' || k == 'photo' || k == 'text' || k == 'content') return text;
      return keepMissing ? m[0]! : '…';
    }).replaceAll(RegExp(r'\s+\n'), '\n').trim();
  }
}
