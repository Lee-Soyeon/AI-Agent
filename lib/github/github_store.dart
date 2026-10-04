import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'github_api.dart';

/// GitHub 연결 상태 (Personal Access Token + owner/repo). 토큰은 보안 저장소에 저장한다.
class GithubStore extends ChangeNotifier {
  GithubStore({FlutterSecureStorage? secure, http.Client? client})
    : _secure = secure ?? const FlutterSecureStorage(),
      _client = client;

  final FlutterSecureStorage _secure;
  final http.Client? _client;

  String token = '';
  String owner = '';
  String repo = '';

  bool get isConnected => token.isNotEmpty && owner.isNotEmpty && repo.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    owner = prefs.getString('github_owner') ?? '';
    repo = prefs.getString('github_repo') ?? '';
    try {
      token = await _secure.read(key: 'github_token') ?? '';
    } catch (_) {
      token = '';
    }
    notifyListeners();
  }

  /// 토큰·저장소 접근을 확인하고 저장한다. 실패하면 예외를 던진다.
  Future<void> connect({required String token, required String owner, required String repo}) async {
    final o = owner.trim();
    final r = repo.trim();
    final t = token.trim();
    await GithubApi(token: t, owner: o, repo: r, client: _client).checkAccess();
    this.token = t;
    this.owner = o;
    this.repo = r;
    await _secure.write(key: 'github_token', value: t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_owner', o);
    await prefs.setString('github_repo', r);
    notifyListeners();
  }

  Future<void> disconnect() async {
    token = '';
    owner = '';
    repo = '';
    await _secure.delete(key: 'github_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('github_owner');
    await prefs.remove('github_repo');
    notifyListeners();
  }

  GithubApi createApi() => GithubApi(token: token, owner: owner, repo: repo, client: _client);
}
