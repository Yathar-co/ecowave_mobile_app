import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// 🔧 Live production backend URL on Render
const String _productionUrl = 'https://ecowavemobile-y4aq.onrender.com';

/// Port used by the local development server
const int _serverPort = 5001;

/// Resolved backend base URL used by the entire app.
String get serverUrl {
  // 🌟 FORCE PRODUCTION FOR THE PRESENTATION APK
  if (_productionUrl.isNotEmpty) return _productionUrl;

  if (kReleaseMode) return _productionUrl;

  // Auto-detect local emulators for local debug mode
  if (kIsWeb) return 'http://localhost:$_serverPort';
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:$_serverPort';
    if (Platform.isIOS) return 'http://localhost:$_serverPort';
  } catch (_) {}
  return 'http://10.0.2.2:$_serverPort';
}
