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

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw != null) {
      _user = User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _api.setToken(_user?.token);
      refreshProfile();
    }
  }

  String _handleError(dynamic e) {
    if (e is DioException) {
      return e.error?.toString() ?? 'An unexpected network error occurred';
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
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '983958658964-c7b2n8l9kj01t1f0mc9dho7rtabriqe6.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );
      
      final GoogleSignInAccount? account = await googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Google Sign-In timed out.'),
      );
      
      if (account == null) return;
      
      await loginWithGoogleManual(account.email, account.displayName ?? account.email.split('@')[0]);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> loginWithGoogleManual(String email, String name) async {
    try {
      _user = await _api.loginWithGoogle(email, name);
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
