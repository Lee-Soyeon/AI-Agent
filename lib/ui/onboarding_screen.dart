import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings_store.dart';
import '../recipes/recipe_catalog.dart';
import 'app_theme.dart';
import 'toss_form.dart';

/// 첫 실행 3문답 (PRD 5.1). 한 화면에 질문 하나, 답은 칩. 건너뛸 수 있다.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onDone});

  /// 저장 뒤 호출. null 이면 Navigator.pop.
  final VoidCallback? onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  String _persona = '';
  String _routine = '';
  String _device = '';
  final _free = TextEditingController();
  bool _freeRoutine = false;

  @override
  void dispose() {
    _free.dispose();
    super.dispose();
  }

  Future<void> _finish({bool skipped = false}) async {
    final settings = context.read<SettingsStore>();
    if (skipped) {
      await settings.saveProfile(persona: settings.persona, routine: settings.routine, device: settings.device);
    } else {
      await settings.saveProfile(persona: _persona, routine: _routine, device: _device);
    }
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _next() {
    if (_step >= 2) {
      _finish();
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<RecipeCatalog?>();
    final personas = catalog?.personas ?? const [
      RecipePersona('student', '학생'),
      RecipePersona('office', '직장인'),
      RecipePersona('parttime', '아르바이트'),
      RecipePersona('owner', '자영업'),
      RecipePersona('home', '은퇴·가정'),
      RecipePersona('jobseeker', '취업 준비'),
      RecipePersona('other', '기타'),
    ];
    final routines = catalog?.routinesFor(_persona.isEmpty ? 'other' : _persona) ?? const ['없음'];
    final t = AppTokens.of(context);

    final (String question, String why, Widget body, bool canNext) = switch (_step) {
      0 => (
        '주로 어떤 일을 하세요?',
        '맞는 할 일을 먼저 보여드리려고요',
        TossChips(
          options: [for (final p in personas) p.label],
          selected: personas.where((p) => p.id == _persona).map((p) => p.label).firstOrNull,
          onSelected: (label) {
            setState(() {
              _persona = personas.firstWhere((p) => p.label == label).id;
              _routine = '';
              _freeRoutine = false;
            });
            Future.delayed(const Duration(milliseconds: 180), _next);
          },
        ),
        _persona.isNotEmpty,
      ),
      1 => (
        '요즘 반복해서 하는 일이 있나요?',
        '그 일부터 바로 시킬 수 있게 할게요',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TossChips(
              options: routines,
              selected: _freeRoutine ? null : (_routine.isEmpty ? null : _routine),
              allowFree: true,
              freeSelected: _freeRoutine,
              onSelected: (v) {
                setState(() {
                  _routine = v;
                  _freeRoutine = false;
                });
                Future.delayed(const Duration(milliseconds: 180), _next);
              },
              onFree: () => setState(() => _freeRoutine = true),
            ),
            if (_freeRoutine) ...[
              const SizedBox(height: 12),
              TossKeywordField(
                controller: _free,
                placeholder: '예: 재고 사진 정리',
                onSubmitted: (v) {
                  setState(() => _routine = v);
                  _next();
                },
              ),
            ],
          ],
        ),
        _routine.isNotEmpty || (_freeRoutine && _free.text.trim().isNotEmpty),
      ),
      _ => (
        '주로 폰이에요, 컴퓨터예요?',
        '화면 크기에 맞춰 보여드릴게요',
        TossChips(
          options: const ['폰', '컴퓨터'],
          selected: _device == 'phone' ? '폰' : (_device == 'computer' ? '컴퓨터' : null),
          onSelected: (v) {
            setState(() => _device = v == '폰' ? 'phone' : 'computer');
            Future.delayed(const Duration(milliseconds: 180), _next);
          },
        ),
        _device.isNotEmpty,
      ),
    };

    return TossFormScaffold(
      step: _step,
      total: 3,
      question: question,
      why: why,
      onBack: _step == 0 ? null : () => setState(() => _step--),
      trailing: TextButton(
        onPressed: () => _finish(skipped: true),
        child: Text('건너뛰기', style: TextStyle(color: t.muted)),
      ),
      nextLabel: _step == 2 ? '시작하기' : '다음',
      onNext: canNext
          ? () {
              if (_step == 1 && _freeRoutine) _routine = _free.text.trim();
              _next();
            }
          : null,
      child: body,
    );
  }
}
