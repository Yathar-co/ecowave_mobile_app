import 'dart:io';
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../config/server_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
      // Allow Dio to throw on 4xx and 5xx so the interceptor handles them globally
      validateStatus: (status) => status! < 400,
    ));

    // Interceptor to inject baseUrl dynamically from serverUrl
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.baseUrl = serverUrl;
        return handler.next(options);
      },
      onError: (e, handler) {
        String userMessage = 'An unexpected error occurred';

        // 0. Detect HTML error responses (like Render 502/504)
        if (e.response?.data is String && (e.response!.data as String).contains('<!DOCTYPE html>')) {
          userMessage = 'Server is waking up or temporarily unavailable. Please try again in 30 seconds.';
        }
        // 1. Try to extract specific error from JSON response body
        else if (e.response?.data is Map) {
          final data = e.response!.data as Map;
          userMessage = data['error'] ?? data['message'] ?? userMessage;
        } 
        // 2. Otherwise use status-based or network-based messages
        else if (e.type == DioExceptionType.connectionTimeout || 
            e.type == DioExceptionType.receiveTimeout) {
          userMessage = 'Connection timed out. Please check your internet.';
        } else if (e.type == DioExceptionType.connectionError || e.error is SocketException) {
          userMessage = 'Cannot connect to server. Please check your connection.';
        } else if (e.response?.statusCode == 401) {
          userMessage = 'Invalid credentials or session expired.';
          if (e.requestOptions.headers.containsKey('Authorization')) {
            setToken(null);
          }
        } else if (e.response?.statusCode == 404) {
          userMessage = 'Requested resource not found. Check backend URL.';
        } else if (e.response?.statusCode != null && e.response!.statusCode! >= 500) {
          userMessage = 'Server error. We are working to fix this.';
        }

        // Return a new DioException with the friendly message as the message
        return handler.next(e.copyWith(message: userMessage));
      },
    ));

    // Retry interceptor for Render cold start (502/503/504 and connection errors)
    _dio.interceptors.add(_RetryInterceptor(_dio));

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

  Future<User> login(String email, String password) async {
    final res = await _dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });
    
    final data = res.data;
    if (data is String && (data.contains('<!DOCTYPE html>') || data.contains('<html'))) {
      throw Exception('Server is waking up. Please wait 1 minute and try again.');
    }
    if (data is! Map) {
      // Log the unexpected response for debugging
      print('Unexpected Server Response (Login): $data');
      throw Exception('Server returned an invalid format. Please try again.');
    }
    
    if (data['user'] == null) throw Exception(data['error'] ?? 'Login failed');
    final token = data['token'] as String;
    final userMap = Map<String, dynamic>.from(data['user'] as Map);
    userMap['token'] = token;
    return User.fromJson(userMap);
  }

  Future<User> register({
    required String email,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final res = await _dio.post('/api/auth/register', data: {
      'email': email,
      'username': username,
      'password': password,
      'confirm_password': confirmPassword,
    });
    
    final data = res.data;
    if (data is String && (data.contains('<!DOCTYPE html>') || data.contains('<html'))) {
      throw Exception('Server is temporarily unavailable. Please try again in 30 seconds.');
    }
    if (data is! Map) {
      print('Unexpected Server Response (Register): $data');
      throw Exception('Invalid server response. Please try again.');
    }

    if (data['user'] == null) throw Exception(data['error'] ?? 'Registration failed');
    final token = data['token'] as String;
    final userMap = Map<String, dynamic>.from(data['user'] as Map);
    userMap['token'] = token;
    return User.fromJson(userMap);
  }

  Future<User> loginWithGoogle({required String email, required String name, String? idToken}) async {
    final body = <String, dynamic>{
      'email': email,
      'name': name,
    };
    if (idToken != null) {
      body['id_token'] = idToken;
    }

    final res = await _dio.post('/api/auth/google', data: body);
    final data = res.data;
    if (data is! Map) throw Exception('Server returned an invalid response.');
    if (data['user'] == null) throw Exception(data['error'] ?? 'Google login failed');
    final token = data['token'] as String;
    final userMap = Map<String, dynamic>.from(data['user'] as Map);
    userMap['token'] = token;
    return User.fromJson(userMap);
  }

  // ── Products ─────────────────────────────────────────────────────────────
  Future<List<Product>> getProducts({
    String? category,
    String? search,
    String? excludeSeller,
  }) async {
    final params = <String, dynamic>{};
    if (category != null && category != 'all') params['category'] = category;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (excludeSeller != null && excludeSeller.isNotEmpty) params['exclude_seller'] = excludeSeller;

    final res = await _dio.get('/api/products', queryParameters: params);
    final data = res.data;
    if (data is String && (data.contains('<!DOCTYPE html>') || data.contains('<html'))) {
      return []; // Return empty list while server wakes up
    }
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

// ── Retry Interceptor for Render Cold Start ─────────────────────────────────
class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const _maxRetries = 3;
  static const _retryHeader = 'x-retry-count';

  _RetryInterceptor(this._dio);

  bool _shouldRetry(DioException err) {
    // Retry on connection errors (server sleeping)
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.error is SocketException) {
      return true;
    }
    // Retry on 502, 503, 504 (Render cold start responses)
    final status = err.response?.statusCode;
    if (status == 502 || status == 503 || status == 504) return true;
    // Retry on HTML error pages (Render gateway timeout)
    if (err.response?.data is String && (err.response!.data as String).contains('<!DOCTYPE html>')) {
      return true;
    }
    return false;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = int.tryParse(err.requestOptions.headers[_retryHeader]?.toString() ?? '0') ?? 0;

    if (_shouldRetry(err) && retryCount < _maxRetries) {
      final delay = Duration(seconds: 2 * (retryCount + 1)); // 2s, 4s, 6s
      await Future.delayed(delay);

      try {
        final options = err.requestOptions;
        options.headers[_retryHeader] = (retryCount + 1).toString();
        final response = await _dio.fetch(options);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }

    return handler.next(err);
  }
}
