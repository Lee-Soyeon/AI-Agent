import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google OAuth 클라이언트 ID 는 빌드 시 주입한다.
///
/// - Android: Google Cloud 의 "웹 애플리케이션" OAuth 클라이언트 ID 를 serverClientId 로 넘겨야 한다.
///   `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`
/// - iOS: `ios/Flutter/GoogleSignIn.xcconfig` 에 iOS 클라이언트 ID 를 넣으면 Info.plist(GIDClientID)로 들어간다.
///   (원하면 GOOGLE_IOS_CLIENT_ID dart-define 으로 코드에서 넘길 수도 있다.)
/// - 웹: "웹 애플리케이션" OAuth 클라이언트 ID 를 GOOGLE_WEB_CLIENT_ID 로 넘긴다.
///   승인된 JavaScript 원본에 배포 주소(예: https://ai-agent-web-dusky.vercel.app)를 넣어야 한다.
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// 앱 로그인(회원가입)과 Gmail 권한(access token)을 관리한다.
///
/// 로그인은 이름·이메일만 받는다. Gmail 권한은 Gmail 을 연결할 때 따로 받는다.
/// 비밀번호는 앱을 거치지 않고 Google 의 공식 로그인 화면에서만 입력된다.
/// 토큰 저장·갱신은 플랫폼 SDK(Android Credential Manager / iOS GoogleSignIn / 웹 GIS)가 맡는다.
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

  /// 첫 init 이 끝났는지 (로그인 복원 시도 포함). 끝나기 전에는 로그인 화면 대신 로딩을 보인다.
  bool ready = false;

  /// Gmail 권한까지 받았는지.
  bool gmailConnected = false;

  /// 마지막으로 로그인한 계정(이메일·이름). 웹 GIS 는 로그인을 기억하지 않고 One Tap 복원은
  /// 돌아오지 않을 수 있어서, 로그아웃 전까지는 이 값으로 로그인 상태를 유지한다.
  String? _savedEmail;
  String? _savedName;
  static const _kEmail = 'google_login_email', _kName = 'google_login_name';

  bool get isSignedIn => user != null || _savedEmail != null;
  String? get email => user?.email ?? _savedEmail;
  String? get name => user?.displayName ?? _savedName;

  GoogleSignInAuthorizationClient get _authz => user?.authorizationClient ?? _signIn.authorizationClient;

  Future<void> _remember(GoogleSignInAccount? account) async {
    final prefs = await SharedPreferences.getInstance();
    if (account == null) {
      _savedEmail = _savedName = null;
      await prefs.remove(_kEmail);
      await prefs.remove(_kName);
      return;
    }
    _savedEmail = account.email;
    _savedName = account.displayName;
    await prefs.setString(_kEmail, account.email);
    if (account.displayName != null) await prefs.setString(_kName, account.displayName!);
  }

  /// 이 빌드에 클라이언트 ID 가 들어 있으면 앱을 쓰기 전에 로그인을 받는다.
  /// 없으면(로컬 개발 등) 로그인 화면 없이 바로 쓴다.
  static bool get loginRequired =>
      kIsWeb ? _webClientId.isNotEmpty : (_serverClientId.isNotEmpty || _iosClientId.isNotEmpty);

  /// 웹은 authenticate() 를 못 쓰고 Google 이 그려 주는 버튼으로만 로그인한다.
  bool get canAuthenticate => _signIn.supportsAuthenticate();

  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedEmail = prefs.getString(_kEmail);
      _savedName = prefs.getString(_kName);
      final clientId = kIsWeb ? _webClientId : _iosClientId;
      await _signIn.initialize(
        clientId: clientId.isEmpty ? null : clientId,
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _sub = _signIn.authenticationEvents.listen(
        (e) {
          final signedIn = switch (e) {
            GoogleSignInAuthenticationEventSignIn() => e.user,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
          // 웹에서 One Tap 세션이 끝나 SignOut 이벤트가 와도 앱 로그인은 유지한다 (로그아웃은 signOut 으로만).
          if (signedIn != null) unawaited(_remember(signedIn));
          user = signedIn;
          if (user == null) gmailConnected = false;
          notifyListeners();
          unawaited(_checkGmail());
        },
        onError: (Object e) {
          // 자동 로그인 창(One Tap)을 닫은 것은 오류가 아니다.
          if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) return;
          error = _describe(e);
          notifyListeners();
        },
      );
      // 이전에 로그인했다면 조용히 복원한다. 웹은 One Tap 창을 띄우므로 저장된 계정이 있으면 하지 않는다.
      if (!(kIsWeb && _savedEmail != null)) await _signIn.attemptLightweightAuthentication();
    } catch (e) {
      error = _describe(e);
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  /// 이미 받은 Gmail 권한이 있는지 창을 띄우지 않고 확인한다.
  Future<void> _checkGmail() async {
    if (!isSignedIn) return;
    try {
      final ok = await _authz.authorizationForScopes(gmailScopes) != null;
      if (ok != gmailConnected) {
        gmailConnected = ok;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 앱 로그인(처음이면 가입). 이름·이메일만 받는다. 반드시 사용자 버튼 탭에서 호출한다.
  /// 웹은 이 대신 [GoogleSignInButton] 을 쓴다.
  Future<bool> signIn() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await init();
      user = await _signIn.authenticate();
      await _remember(user);
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

  /// Gmail 권한을 받는다. 로그인 전이면 로그인부터 한다. 반드시 사용자 버튼 탭에서 호출한다.
  Future<bool> connectGmail() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await init();
      if (user == null && canAuthenticate) {
        user = await _signIn.authenticate(scopeHint: gmailScopes);
        await _remember(user);
      }
      // 웹은 계정 객체 없이도 권한 창을 띄울 수 있다.
      await _authz.authorizeScopes(gmailScopes);
      gmailConnected = true;
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

  /// 로그아웃하고 앱에 준 권한(Gmail 포함)도 철회한다.
  Future<void> signOut() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      await _signIn.signOut();
    }
    user = null;
    gmailConnected = false;
    await _remember(null);
    notifyListeners();
  }

  /// Gmail API 호출용 Authorization 헤더. [refresh] 면 캐시된 토큰을 버리고 새로 받는다.
  Future<Map<String, String>> authHeaders({bool refresh = false, String? staleToken}) async {
    if (!isSignedIn) throw GoogleAuthRequired('Google 계정이 연결되어 있지 않습니다.');
    final u = _authz;
    if (refresh && staleToken != null) {
      await u.clearAuthorizationToken(accessToken: staleToken);
    }
    var headers = await u.authorizationHeaders(gmailScopes);
    if (headers == null && !_signIn.authorizationRequiresUserInteraction()) {
      headers = await u.authorizationHeaders(
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
      return 'Google 로그인을 쓰려면 Google OAuth 클라이언트 ID 설정이 필요합니다 '
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
