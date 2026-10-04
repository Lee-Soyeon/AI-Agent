import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'slack_api.dart';
import 'slack_oauth_service.dart';

/// Slack 연결 상태(Bot Token + 보낼 채널). 토큰은 보안 저장소, 채널은 SharedPreferences 에 저장한다.
class SlackStore extends ChangeNotifier {
  SlackStore({FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  String botToken = '';
  String channelId = '';
  String channelName = '';
  String teamName = '';

  bool get isConnected => botToken.isNotEmpty && channelId.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    channelId = prefs.getString('slack_channelId') ?? '';
    channelName = prefs.getString('slack_channelName') ?? '';
    teamName = prefs.getString('slack_teamName') ?? '';
    try {
      botToken = await _secure.read(key: 'slack_botToken') ?? '';
    } catch (_) {
      botToken = '';
    }
    notifyListeners();
  }

  /// 토큰이 유효한지 확인하고 저장한다. 실패하면 예외를 던진다.
  Future<void> connect(String token) async {
    final auth = await SlackApi(botToken: token.trim()).authTest();
    botToken = token.trim();
    teamName = auth.team;
    await _secure.write(key: 'slack_botToken', value: botToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('slack_teamName', teamName);
    notifyListeners();
  }

  /// OAuth 연동 결과(중계 서버가 이미 교환해 준 토큰)를 그대로 저장한다.
  /// 이미 Slack 이 발급한 유효한 토큰이므로 auth.test 를 다시 부르지 않는다.
  Future<void> connectWithOAuth(SlackOAuthResult result) async {
    botToken = result.botToken;
    teamName = result.teamName;
    await _secure.write(key: 'slack_botToken', value: botToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('slack_teamName', teamName);
    notifyListeners();
  }

  Future<void> setChannel(SlackChannel channel) async {
    channelId = channel.id;
    channelName = channel.name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('slack_channelId', channelId);
    await prefs.setString('slack_channelName', channelName);
    notifyListeners();
  }

  Future<void> disconnect() async {
    botToken = '';
    channelId = '';
    channelName = '';
    teamName = '';
    await _secure.delete(key: 'slack_botToken');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('slack_channelId');
    await prefs.remove('slack_channelName');
    await prefs.remove('slack_teamName');
    notifyListeners();
  }

  SlackApi createApi() => SlackApi(botToken: botToken);
}
