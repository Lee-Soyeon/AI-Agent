import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google OAuth 클라이언트 ID 는 빌드 시 주입한다.
///
/// - Android: Google Cloud 의 "웹 애플리케이션" OAuth 클라이언트 ID 를 serverClientId 로 넘겨야 한다.
///   `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`
/// - iOS: `ios/Flutter/GoogleSignIn.xcconfig` 에 iOS 클라이언트 ID 를 넣으면 Info.plist(GIDClientID)로 들어간다.
///   (원하면 GOOGLE_IOS_CLIENT_ID dart-define 으로 코드에서 넘길 수도 있다.)
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

/// Google 로그인과 Gmail 권한(access token)을 관리한다.
///
/// 비밀번호는 앱을 거치지 않고 Google 의 공식 로그인 화면에서만 입력된다.
/// 토큰 저장·갱신은 플랫폼 SDK(Android Credential Manager / iOS GoogleSignIn)가 맡는다.
class GoogleAuthService extends ChangeNotifier {
  static const gmailScopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
  ];

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;
  Future<void>? _init;

  GoogleSignInAccount? user;
  bool busy = false;
  String? error;

  bool get isSignedIn => user != null;
  String? get email => user?.email;

  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      await _signIn.initialize(
        clientId: _iosClientId.isEmpty ? null : _iosClientId,
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _sub = _signIn.authenticationEvents.listen(
        (e) {
          user = switch (e) {
            GoogleSignInAuthenticationEventSignIn() => e.user,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
          notifyListeners();
        },
        onError: (Object e) {
          error = _describe(e);
          notifyListeners();
        },
      );
      // 이전에 로그인했다면 조용히 복원한다.
      await _signIn.attemptLightweightAuthentication();
    } catch (e) {
      error = _describe(e);
      notifyListeners();
    }
  }

  /// 반드시 사용자 버튼 탭에서 호출한다 (일부 플랫폼은 권한 요청에 사용자 상호작용이 필요).
  Future<bool> signIn() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await init();
      final account = await _signIn.authenticate(scopeHint: gmailScopes);
      // 로그인과 같은 탭 안에서 Gmail 권한까지 받아 둔다.
      await account.authorizationClient.authorizeScopes(gmailScopes);
      user = account;
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) error = _describe(e);
      return false;
    } catch (e) {
      error = _describe(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 로그아웃하고 앱에 준 Gmail 권한도 철회한다.
  Future<void> signOut() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      await _signIn.signOut();
    }
    user = null;
    notifyListeners();
  }

  /// Gmail API 호출용 Authorization 헤더. [refresh] 면 캐시된 토큰을 버리고 새로 받는다.
  Future<Map<String, String>> authHeaders({bool refresh = false, String? staleToken}) async {
    final u = user;
    if (u == null) throw GoogleAuthRequired('Google 계정이 연결되어 있지 않습니다.');
    if (refresh && staleToken != null) {
      await u.authorizationClient.clearAuthorizationToken(accessToken: staleToken);
    }
    var headers = await u.authorizationClient.authorizationHeaders(gmailScopes);
    if (headers == null && !_signIn.authorizationRequiresUserInteraction()) {
      headers = await u.authorizationClient.authorizationHeaders(
        gmailScopes,
        promptIfNecessary: true,
      );
    }
    if (headers == null) {
      throw GoogleAuthRequired('Gmail 권한이 만료되었습니다. 홈 화면에서 Google 계정을 다시 연결해 주세요.');
    }
    return headers;
  }

  static String _describe(Object e) {
    // 클라이언트 ID 를 아직 설정하지 않은 경우 (iOS: GIDClientID 비어 있음, Android: serverClientId 없음)
    if (RegExp(
      r'clientID|serverClientId|No active configuration',
      caseSensitive: false,
    ).hasMatch('$e')) {
      return 'Gmail 연결을 쓰려면 Google OAuth 클라이언트 ID 설정이 필요합니다 '
          '(README 의 "Gmail(Google 로그인) 설정"). 서버 모드에서는 필요 없습니다.';
    }
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        return 'Google 로그인 설정 오류: OAuth 클라이언트 ID 를 확인하세요. (${e.description ?? ''})';
      }
      return 'Google 로그인 실패 (${e.code.name}): ${e.description ?? ''}';
    }
    return 'Google 로그인 실패: $e';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class GoogleAuthRequired implements Exception {
  GoogleAuthRequired(this.message);
  final String message;
  @override
  String toString() => message;
}
