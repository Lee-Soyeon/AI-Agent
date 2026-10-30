import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Google Identity Services 버튼. 누르면 GoogleAuthService 의 authenticationEvents 로 로그인이 들어온다.
Widget googleWebButton() => web.renderButton(
  configuration: web.GSIButtonConfiguration(
    type: web.GSIButtonType.standard,
    theme: web.GSIButtonTheme.outline,
    size: web.GSIButtonSize.large,
    text: web.GSIButtonText.continueWith,
    shape: web.GSIButtonShape.pill,
    minimumWidth: 320,
    locale: 'ko',
  ),
);
