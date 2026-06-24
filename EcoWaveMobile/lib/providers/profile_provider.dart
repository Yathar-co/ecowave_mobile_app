import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ProfileProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Product> _listings = [];
  List<Product> _purchases = [];
  List<Review> _reviews = [];
  List<Map<String, dynamic>> _inquiries = [];
  ImpactStats? _impactStats;
  bool _isLoading = false;
  String? _error;

  List<Product> get listings => _listings;
  List<Product> get purchases => _purchases;
  List<Review> get reviews => _reviews;
  List<Map<String, dynamic>> get inquiries => _inquiries;
  ImpactStats? get impactStats => _impactStats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _listings = await _api.getProductsBySeller(email);
      _purchases = await _api.getPurchasedProducts();
      _reviews = await _api.getSellerReviews(email);
      _inquiries = await _api.getSellerInquiries();
    } catch (e) {
      _error = e.toString().replaceAll('DioException', 'Network error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Load impact stats silently (doesn't block UI)
    _impactStats = await _api.getUserImpact();
    notifyListeners();
  }

  Future<void> addReview({required String productId, required double rating, required String comment}) async {
    await _api.createReview(productId: productId, rating: rating, comment: comment);
  }

  Future<void> deleteListing(String id) async {
    try {
      await _api.deleteProduct(id);
      _listings = _listings.where((p) => p.id != id).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAsShipped(String txnId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      await _api.markAsShipped(txnId);
      // Reload to reflect changes
      if (_listings.isNotEmpty) {
        // Find the email from the listing that was just shipped
        final listing = _listings.firstWhere((p) => p.txnId == txnId);
        _listings = await _api.getProductsBySeller(listing.sellerEmail);
      }
    } catch (e) {
      _error = e.toString().replaceAll('DioException', 'Error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendInquiry(InquiryRequest req) async {
    try {
      await _api.sendInquiry(req);
      return true;
    } catch (_) {
      return false;
    }
  }
}
