import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'work_filter_models.dart';

/// 처리한 공유 항목 기록 (최신 순). 기기에만 저장하고 최대 [_max] 개까지만 남긴다.
class WorkFilterStore extends ChangeNotifier {
  static const _max = 200;
  static const _key = 'workFilter_items';

  final List<SharedItem> items = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => SharedItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        items
          ..clear()
          ..addAll(list);
      } catch (_) {
        // 손상된 기록은 무시한다.
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final i in items) i.toJson()]));
  }

  Future<void> upsert(SharedItem item) async {
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.insert(0, item);
      while (items.length > _max) {
        items.removeLast();
      }
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    items.clear();
    notifyListeners();
    await _persist();
  }
}
