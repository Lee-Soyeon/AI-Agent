import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/settings_store.dart';
import '../slack/slack_store.dart';
import 'work_filter_models.dart';
import 'work_filter_service.dart';
import 'work_filter_store.dart';

/// 에이닷/문자 앱의 "공유" 버튼으로 들어온 텍스트를 받아 분류·Slack 전송까지 흘려보낸다.
///
/// iOS 는 Share Extension(네이티브, Xcode 에서 한 번 추가 필요)이 있어야 공유 시트에 이 앱이 나타난다.
/// 자세한 설정은 docs/work-filter-slack-setup.md 참고.
class ShareIntentController extends ChangeNotifier {
  ShareIntentController({
    required this.settings,
    required this.slack,
    required this.store,
    WorkFilterService? service,
  }) : _service = service ?? const WorkFilterService();

  final SettingsStore settings;
  final SlackStore slack;
  final WorkFilterStore store;
  final WorkFilterService _service;

  StreamSubscription<List<SharedMediaFile>>? _sub;
  String? lastError;

  Future<void> init() async {
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handle,
      onError: (Object e) {
        lastError = '$e';
        notifyListeners();
      },
    );
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) await _handle(initial);
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    for (final f in files) {
      final text = _extractText(f);
      if (text == null || text.trim().isEmpty) continue;
      final item = SharedItem(
        id: 'share_${DateTime.now().microsecondsSinceEpoch}',
        receivedAt: DateTime.now(),
        rawText: text.trim(),
      );
      unawaited(_service.process(item: item, settings: settings, slack: slack, store: store));
    }
    await ReceiveSharingIntent.instance.reset();
  }

  String? _extractText(SharedMediaFile f) {
    if (f.type != SharedMediaType.text && f.type != SharedMediaType.url) return null;
    final text = f.text;
    return (text != null && text.isNotEmpty) ? text : f.path;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
