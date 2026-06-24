import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  User? get user => _user;
  bool get isLoggedIn => _user != null;

  final ApiService _api = ApiService();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '328504803059-hqofqob66a16dp21rlvrg7t0mh5ekscp.apps.googleusercontent.com',
  );

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw != null) {
      _user = User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _api.setToken(_user?.token);
      
      // Verify if the token is still valid by making a protected call
      try {
        await _api.getUserImpact(); 
        refreshProfile();
      } catch (e) {
        if (e.toString().contains('401') || e.toString().contains('expired')) {
          logout(); // Token is dead, clear session
        }
      }
    }
  }

  String _handleError(dynamic e) {
    if (e is DioException) {
      if (e.response?.statusCode == 401) {
        logout(); // Auto-logout on expired token
        return 'Session expired. Please login again.';
      }
      final data = e.response?.data;
      if (data is Map && data.containsKey('message')) {
        return data['message'];
      }
      return e.message ?? 'An unexpected network error occurred';
    }
    return e.toString();
  }

  Future<void> refreshProfile() async {
    if (_user == null) return;
    try {
      final updated = await _api.getUserProfile(_user!.email);
      _user = User(
        email: updated.email,
        name: updated.name,
        token: _user!.token,
        phone: updated.phone,
        isVerified: updated.isVerified,
        isTrustedSeller: updated.isTrustedSeller,
        rating: updated.rating,
        salesCount: updated.salesCount,
        createdAt: updated.createdAt,
        isBanned: updated.isBanned,
        banReason: updated.banReason,
        reportCount: updated.reportCount,
      );
      await _persist();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> login(String email, String password) async {
    try {
      _user = await _api.login(email, password);
      _api.setToken(_user?.token);
      await _persist();
    } catch (e) {
      _user = null;
      _api.setToken(null);
      throw _handleError(e);
    }
    notifyListeners();
  }

  Future<void> register({
    required String email,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      _user = await _api.register(
        email: email,
        username: username,
        password: password,
        confirmPassword: confirmPassword,
      );
      _api.setToken(_user?.token);
      await _persist();
    } catch (e) {
      _user = null;
      _api.setToken(null);
      throw _handleError(e);
    }
    notifyListeners();
  }

  Future<void> loginWithGoogle() async {
    try {
      // Disconnect first to ensure the user can pick an account if they failed previously
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? account = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Google Sign-In timed out.'),
      );
      
      if (account == null) return;

      // Get the ID token for server-side verification
      String? idToken;
      try {
        final auth = await account.authentication;
        idToken = auth.idToken;
      } catch (_) {
        // If we can't get the ID token, fall back to email-only (dev mode)
      }
      
      await loginWithGoogleManual(account.email, account.displayName ?? account.email.split('@')[0], idToken: idToken);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> loginWithGoogleManual(String email, String name, {String? idToken}) async {
    try {
      _user = await _api.loginWithGoogle(email: email, name: name, idToken: idToken);
      _api.setToken(_user?.token);
      await _persist();
      notifyListeners();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> logout() async {
    _user = null;
    _api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_user != null) {
      await prefs.setString('user', jsonEncode(_user!.toJson()));
    }
  }
}
