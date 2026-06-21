import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class SellProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _isLoading = false;
  bool _success = false;
  String? _error;

  bool get isLoading => _isLoading;
  bool get success => _success;
  String? get error => _error;

  /// Optional callback to invalidate marketplace cache after listing
  VoidCallback? onProductListed;

  Future<void> listProduct(CreateProductRequest req) async {
    _isLoading = true;
    _success = false;
    _error = null;
    notifyListeners();
    try {
      await _api.createProduct(req);
      _success = true;
      // Invalidate marketplace cache so new listing appears
      onProductListed?.call();
    } catch (e) {
      _error = e.toString().replaceAll('DioException', 'Network error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _success = false;
    _error = null;
    notifyListeners();
  }
}
