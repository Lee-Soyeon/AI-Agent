// 웹은 Google 이 그려 주는 로그인 버튼만 쓸 수 있어서 플랫폼별로 나눈다.
export 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart';
