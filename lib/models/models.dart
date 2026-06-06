// ── Data models (mirrors Kotlin Models.kt) ──────────────────────────────────

class EcoImpact {
  final double co2;
  final double water;
  final double waste;

  const EcoImpact({this.co2 = 0, this.water = 0, this.waste = 0});

  factory EcoImpact.fromJson(Map<String, dynamic> j) => EcoImpact(
        co2: (j['co2'] as num?)?.toDouble() ?? 0,
        water: (j['water'] as num?)?.toDouble() ?? 0,
        waste: (j['waste'] as num?)?.toDouble() ?? 0,
      );
}

class Product {
  final String id;
  final String title;
  final String description;
  final double price;
  final String badge;
  final String image;
  final String category;
  final String material;
  final EcoImpact? ecoImpact;
  final String sellerId;
  final String sellerEmail;
  final String sellerLocation;
  final Map<String, double>? location; // {lat: ..., lng: ...}
  final String sellerPhone;
  final String sellerUpiId;
  final String createdAt;
  final String status;
  final String? txnId;
  final String? buyerEmail;

  const Product({
    this.id = '',
    this.title = '',
    this.description = '',
    this.price = 0,
    this.badge = '',
    this.image = '',
    this.category = '',
    this.material = '',
    this.ecoImpact,
    this.sellerId = '',
    this.sellerEmail = '',
    this.sellerLocation = '',
    this.location,
    this.sellerPhone = '',
    this.sellerUpiId = '',
    this.createdAt = '',
    this.status = 'active',
    this.txnId,
    this.buyerEmail,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        badge: j['badge'] as String? ?? '',
        image: j['image'] as String? ?? '',
        category: j['category'] as String? ?? '',
        material: j['material'] as String? ?? '',
        ecoImpact: j['eco_impact'] != null
            ? EcoImpact.fromJson(Map<String, dynamic>.from(j['eco_impact'] as Map))
            : null,
        sellerId: j['seller_id'] as String? ?? '',
        sellerEmail: j['seller_email'] as String? ?? '',
        sellerLocation: j['seller_location'] as String? ?? '',
        location: j['location'] != null 
            ? {
                'lat': (j['location']['lat'] as num).toDouble(),
                'lng': (j['location']['lng'] as num).toDouble(),
              }
            : null,
        sellerPhone: j['seller_phone'] as String? ?? '',
        sellerUpiId: j['seller_upi_id'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        status: j['status'] as String? ?? 'active',
        txnId: j['txn_id'] as String?,
        buyerEmail: j['buyer_email'] as String?,
      );
}

class ImpactStats {
  final double co2Saved;
  final double waterSaved;
  final double wasteSaved;
  final int itemsRecycled;
  final int itemsPurchased;

  const ImpactStats({
    this.co2Saved = 0,
    this.waterSaved = 0,
    this.wasteSaved = 0,
    this.itemsRecycled = 0,
    this.itemsPurchased = 0,
  });

  factory ImpactStats.fromJson(Map<String, dynamic> j) => ImpactStats(
        co2Saved: (j['co2_saved'] as num?)?.toDouble() ?? 0,
        waterSaved: (j['water_saved'] as num?)?.toDouble() ?? 0,
        wasteSaved: (j['waste_saved'] as num?)?.toDouble() ?? 0,
        itemsRecycled: j['items_recycled'] as int? ?? 0,
        itemsPurchased: j['items_purchased'] as int? ?? 0,
      );
}

class User {
  final String email;
  final String name;
  final String token;
  final String phone;
  final bool isVerified;
  final bool isTrustedSeller;
  final double rating;
  final int salesCount;
  final String createdAt;
  final bool isBanned;
  final String? banReason;
  final int reportCount;

  const User({
    this.email = '',
    this.name = '',
    this.token = '',
    this.phone = '',
    this.isVerified = false,
    this.isTrustedSeller = false,
    this.rating = 0.0,
    this.salesCount = 0,
    this.createdAt = '',
    this.isBanned = false,
    this.banReason,
    this.reportCount = 0,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        email: j['email'] as String? ?? '',
        name: j['name'] as String? ?? '',
        token: j['token'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        isVerified: j['is_verified'] as bool? ?? false,
        isTrustedSeller: j['is_trusted_seller'] as bool? ?? false,
        rating: (j['rating'] as num?)?.toDouble() ?? 0.0,
        salesCount: j['sales_count'] as int? ?? 0,
        createdAt: j['created_at'] as String? ?? '',
        isBanned: j['is_banned'] as bool? ?? false,
        banReason: j['ban_reason'] as String?,
        reportCount: j['report_count'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        'token': token,
        'phone': phone,
        'is_verified': isVerified,
        'is_trusted_seller': isTrustedSeller,
        'rating': rating,
        'sales_count': salesCount,
        'created_at': createdAt,
        'is_banned': isBanned,
        'ban_reason': banReason,
        'report_count': reportCount,
      };
}

class Review {
  final String id;
  final String productId;
  final String reviewerName;
  final String reviewerEmail;
  final String comment;
  final double rating;
  final List<String> images;
  final String createdAt;

  const Review({
    required this.id,
    required this.productId,
    required this.reviewerName,
    required this.reviewerEmail,
    required this.comment,
    required this.rating,
    this.images = const [],
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: j['id'] as String? ?? '',
        productId: j['product_id'] as String? ?? '',
        reviewerName: j['reviewer_name'] as String? ?? '',
        reviewerEmail: j['reviewer_email'] as String? ?? '',
        comment: j['comment'] as String? ?? '',
        rating: (j['rating'] as num?)?.toDouble() ?? 0.0,
        images: (j['images'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        createdAt: j['created_at'] as String? ?? '',
      );
}

class InquiryRequest {
  final String productId;
  final String buyerName;
  final String buyerEmail;
  final String buyerMessage;

  const InquiryRequest({
    required this.productId,
    required this.buyerName,
    required this.buyerEmail,
    required this.buyerMessage,
  });

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'buyer_name': buyerName,
        'buyer_email': buyerEmail,
        'buyer_message': buyerMessage,
      };
}

class CreateProductRequest {
  final String title;
  final String description;
  final double price;
  final String badge;
  final String image;
  final String category;
  final String material;
  final String sellerEmail;
  final String sellerLocation;
  final Map<String, double>? location;
  final String sellerUpiId;
  final String sellerId;

  const CreateProductRequest({
    required this.title,
    required this.description,
    required this.price,
    required this.badge,
    required this.image,
    required this.category,
    required this.material,
    required this.sellerEmail,
    required this.sellerLocation,
    this.location,
    this.sellerUpiId = '',
    this.sellerId = 'anonymous',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'price': price,
        'badge': badge,
        'image': image,
        'category': category,
        'material': material,
        'seller_email': sellerEmail,
        'seller_location': sellerLocation,
        'location': location,
        'seller_upi_id': sellerUpiId,
        'seller_id': sellerId,
      };
}

class ChatMessage {
  final String sender;
  final String text;
  final String createdAt;
  final bool isMe;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.createdAt,
    this.isMe = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j, String myEmail) => ChatMessage(
        sender: j['sender'] as String? ?? '',
        text: j['text'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        isMe: j['sender'] == myEmail,
      );
}
