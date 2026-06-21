import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class MarketplaceProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Product> _products = [];
  bool _isLoading = false;
  String? _error;
  String _selectedCategory = 'all';
  String _searchQuery = '';
  String? _currentUserEmail;

  // ── Caching ──────────────────────────────────────────────────────────────
  DateTime? _lastFetchTime;
  String? _cachedCategory;
  String? _cachedSearch;
  static const _cacheDuration = Duration(seconds: 60);

  // ── Race condition prevention ────────────────────────────────────────────
  int _loadId = 0;

  // ── Search debounce ──────────────────────────────────────────────────────
  Timer? _searchDebounce;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;

  void setUserEmail(String? email) {
    _currentUserEmail = email;
  }

  Future<void> loadProducts({bool forceRefresh = false}) async {
    // Check if we can use cached results
    if (!forceRefresh &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration &&
        _cachedCategory == _selectedCategory &&
        _cachedSearch == _searchQuery &&
        _products.isNotEmpty) {
      return; // Use cached results
    }

    final thisLoadId = ++_loadId; // Increment to invalidate older requests

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await _api.getProducts(
        category: _selectedCategory,
        search: _searchQuery,
        excludeSeller: _currentUserEmail,
      );

      // Only apply results if this is still the latest request
      if (thisLoadId != _loadId) return;

      _products = results;
      _lastFetchTime = DateTime.now();
      _cachedCategory = _selectedCategory;
      _cachedSearch = _searchQuery;
    } catch (e) {
      if (thisLoadId != _loadId) return;
      _error = e.toString().replaceAll('DioException', 'Network error');
    } finally {
      if (thisLoadId == _loadId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void setCategory(String cat) {
    if (_selectedCategory == cat) return;
    _selectedCategory = cat;
    loadProducts(forceRefresh: true);
  }

  void setSearch(String q) {
    _searchQuery = q;
    // Debounce search to avoid hammering the API on every keystroke
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      loadProducts(forceRefresh: true);
    });
  }

  /// Call this after creating, editing, or deleting a listing
  void invalidateCache() {
    _lastFetchTime = null;
    _cachedCategory = null;
    _cachedSearch = null;
  }

  void refresh() => loadProducts(forceRefresh: true);

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
