import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// ─────────────────────────────────────────────────────────────────────────────
/// CENTRAL SERVER CONFIGURATION
/// ─────────────────────────────────────────────────────────────────────────────
/// Change the values below to match your deployment.
///
/// For LOCAL development (emulator):
///   - Android Emulator uses 10.0.2.2 to reach the host machine's localhost
///   - iOS Simulator can use localhost directly
///
/// For REAL DEVICE testing on same Wi-Fi:
///   - Set [_productionUrl] to your computer's LAN IP, e.g. 'http://192.168.1.5:5001'
///
/// For DEPLOYED backend (e.g. Render, Railway, AWS):
///   - Set [_productionUrl] to your deployed URL, e.g. 'https://ecowave-api.onrender.com'
/// ─────────────────────────────────────────────────────────────────────────────

/// 🔧 SET YOUR DEPLOYED / LAN BACKEND URL HERE
/// Leave empty to auto-detect for emulator usage.
const String _productionUrl = 'http://192.168.29.225:5001';

/// Port used by the backend server
const int _serverPort = 5001;

/// Resolved backend base URL used by the entire app.
String get serverUrl {
  // If a production URL is explicitly set, always use it
  if (_productionUrl.isNotEmpty) return _productionUrl;

  // Auto-detect for local development
  if (kIsWeb) return 'http://localhost:$_serverPort';
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:$_serverPort';
    if (Platform.isIOS) return 'http://localhost:$_serverPort';
  } catch (_) {}
  return 'http://10.0.2.2:$_serverPort';
}
