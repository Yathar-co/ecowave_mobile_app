import 'package:dio/dio.dart';
import '../models/models.dart';
import '../config/server_config.dart';

final String _baseUrl = serverUrl;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      // Prevents 401/403 from throwing a "Bad Response" exception screen
      validateStatus: (status) => status! < 500,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) {
        // Only clear token if we get a 401 on a request that actually sent a token
        if (e.response?.statusCode == 401 && e.requestOptions.headers.containsKey('Authorization')) {
          setToken(null);
        }
        return handler.next(e);
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      request: false,
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }

  // ── Auth helper ──────────────────────────────────────────────────────────
  String? _token;
  void setToken(String? token) => _token = token;

  Options get _authOptions => Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      });

  Future<User> login(String email, String name) async {
    final res = await _dio.post('/api/auth/login', data: {
      'email': email,
      'name': name,
    });
    final data = res.data;
    if (data['user'] == null) throw Exception(data['error'] ?? 'Login failed');
    final token = data['token'] as String;
    final userMap = Map<String, dynamic>.from(data['user'] as Map);
    userMap['token'] = token;
    return User.fromJson(userMap);
  }

  // ── Products ─────────────────────────────────────────────────────────────
  Future<List<Product>> getProducts({
    String? category,
    String? search,
  }) async {
    final params = <String, dynamic>{};
    if (category != null && category != 'all') params['category'] = category;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final res = await _dio.get('/api/products', queryParameters: params);
    final data = res.data;
    if (data is! Map || data['products'] == null) return [];
    
    final list = data['products'] as List<dynamic>;
    return list
        .where((e) => e != null)
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Product> getProduct(String id) async {
    final res = await _dio.get('/api/products/$id');
    final data = res.data;
    if (data is! Map || data['product'] == null) throw Exception('Product not found');
    return Product.fromJson(Map<String, dynamic>.from(data['product'] as Map));
  }

  Future<Product> createProduct(CreateProductRequest req) async {
    final res = await _dio.post('/api/products', data: req.toJson(), options: _authOptions);
    final data = res.data;
    if (data is! Map || data['product'] == null) {
      final errorMsg = data is Map ? (data['error'] ?? data['message']) : null;
      throw Exception(errorMsg ?? 'Failed to create product');
    }
    return Product.fromJson(Map<String, dynamic>.from(data['product'] as Map));
  }

  Future<void> deleteProduct(String id) async {
    await _dio.delete('/api/products/$id', options: _authOptions);
  }

  Future<List<Product>> getProductsBySeller(String email) async {
    final res = await _dio.get('/api/products/seller/$email');
    final data = res.data;
    if (data is! Map || data['products'] == null) return [];
    
    final list = data['products'] as List<dynamic>;
    return list
        .where((e) => e != null)
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Product>> getPurchasedProducts() async {
    final res = await _dio.get('/api/products/purchased', options: _authOptions);
    final data = res.data;
    if (data is! Map || data['products'] == null) return [];
    
    final list = data['products'] as List<dynamic>;
    return list
        .where((e) => e != null)
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── Reviews ─────────────────────────────────────────────────────────────
  Future<void> createReview({
    required String productId,
    required double rating,
    required String comment,
  }) async {
    await _dio.post('/api/reviews',
        data: {
          'product_id': productId,
          'rating': rating,
          'comment': comment,
        },
        options: _authOptions);
  }

  Future<List<Review>> getSellerReviews(String email) async {
    final res = await _dio.get('/api/reviews/seller/$email');
    final data = res.data;
    if (data is! Map || data['reviews'] == null) return [];
    
    final list = data['reviews'] as List<dynamic>;
    return list
        .map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── Inquiries ────────────────────────────────────────────────────────────
  Future<void> sendInquiry(InquiryRequest req) async {
    await _dio.post('/api/inquiries', data: req.toJson());
  }

  // ── User impact ──────────────────────────────────────────────────────────
  Future<ImpactStats?> getUserImpact() async {
    try {
      final res = await _dio.get('/api/user/impact', options: _authOptions);
      final data = res.data;
      if (data is Map && data['impact'] != null) {
        return ImpactStats.fromJson(Map<String, dynamic>.from(data['impact'] as Map));
      }
    } catch (_) {}
    return null;
  }

  // ── UPI Payments ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> createTransaction({
    required String productId,
    required String buyerEmail,
    required String sellerUpiId,
    required double amount,
  }) async {
    final res = await _dio.post('/api/payments/create-transaction',
        data: {
          'product_id': productId,
          'buyer_email': buyerEmail,
          'seller_upi_id': sellerUpiId,
          'amount': amount,
        },
        options: _authOptions);
    final data = res.data;
    if (data is! Map || data['transaction'] == null) throw Exception('Failed to initiate transaction');
    return Map<String, dynamic>.from(data['transaction'] as Map);
  }

  Future<bool> confirmPayment({
    required String txnId,
    required String productId,
    required String buyerEmail,
  }) async {
    final res = await _dio.post('/api/payments/confirm',
        data: {
          'txn_id': txnId,
          'product_id': productId,
          'buyer_email': buyerEmail,
        },
        options: _authOptions);
    if (res.data['success'] == false) {
      throw Exception(res.data['error'] ?? 'Payment confirmation failed');
    }
    return res.data['success'] == true;
  }

  Future<Map<String, dynamic>> getBill(String txnId) async {
    final res = await _dio.get('/api/payments/bill/$txnId', options: _authOptions);
    final data = res.data;
    if (data is! Map || data['bill'] == null) throw Exception('Bill not found');
    return Map<String, dynamic>.from(data['bill'] as Map);
  }

  Future<void> confirmDelivery(String txnId) async {
    final res = await _dio.post('/api/payments/confirm-delivery', data: {'txn_id': txnId}, options: _authOptions);
    if (res.data['success'] == false) throw Exception(res.data['error'] ?? 'Confirmation failed');
  }

  Future<void> disputeTransaction(String txnId, String reason) async {
    final res = await _dio.post('/api/payments/dispute', data: {'txn_id': txnId, 'reason': reason}, options: _authOptions);
    if (res.data['success'] == false) throw Exception(res.data['error'] ?? 'Dispute failed');
  }

  Future<void> markAsShipped(String txnId) async {
    final res = await _dio.post('/api/seller/mark-shipped', data: {'txn_id': txnId}, options: _authOptions);
    if (res.data['success'] == false) throw Exception(res.data['error'] ?? 'Failed to mark as shipped');
  }

  // ── Reports ─────────────────────────────────────────────────────────────
  Future<void> submitReport({
    required String targetId,
    required String targetType,
    required String reason,
    String description = '',
  }) async {
    await _dio.post('/api/reports',
        data: {
          'target_id': targetId,
          'target_type': targetType,
          'reason': reason,
          'description': description,
        },
        options: _authOptions);
  }

  // ── User Profiles ────────────────────────────────────────────────────────
  Future<User> getUserProfile(String email) async {
    final res = await _dio.get('/api/users/$email');
    final data = res.data;
    if (data is! Map || data['user'] == null) throw Exception(data['error'] ?? 'User not found');
    return User.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }
}
