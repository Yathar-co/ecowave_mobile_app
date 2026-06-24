import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class SellerDashboard extends StatefulWidget {
  const SellerDashboard({super.key});

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        context.read<ProfileProvider>().load(user.email);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final user = context.watch<AuthProvider>().user;
    
    // Average rating calculation
    double avgRating = 0;
    if (profile.reviews.isNotEmpty) {
      avgRating = profile.reviews.map((r) => r.rating).reduce((a, b) => a + b) / profile.reviews.length;
    }

    return Scaffold(
      backgroundColor: ecoDark,
      appBar: AppBar(
        backgroundColor: ecoSurface,
        title: const Text('Seller Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (user != null) await profile.load(user.email);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Performance Summary
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: ecoGreenGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Seller Rating', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          Row(
                            children: [
                              Text(avgRating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              const Icon(Icons.star, color: Colors.orangeAccent, size: 24),
                            ],
                          ),
                          Text('From ${profile.reviews.length} reviews', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      height: 50,
                      width: 1,
                      color: Colors.white24,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(profile.listings.where((p) => p.status == 'sold').length.toString(), 
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          const Text('Items Sold', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text('Active Orders (Shipping Needed)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              _buildShippingList(profile),

              const SizedBox(height: 24),
              const Text('Recent Reviews', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              _buildReviewsList(profile),

              const SizedBox(height: 24),
              const Text('Recent Inquiries', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              _buildInquiriesList(profile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInquiriesList(ProfileProvider profile) {
    if (profile.inquiries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
        child: const Center(child: Text('No inquiries yet', style: TextStyle(color: ecoMuted))),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: profile.inquiries.length,
      itemBuilder: (context, i) {
        final inq = profile.inquiries[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(inq['product_title'] ?? 'Product Inquiry', 
                      style: const TextStyle(color: ecoGreenLight, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(inq['created_at'] != null ? inq['created_at'].toString().split('T')[0] : '', 
                      style: TextStyle(color: ecoMuted, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              Text('From: ${inq['buyer_name']} (${inq['buyer_email']})', 
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('"${inq['buyer_message']}"', 
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShippingList(ProfileProvider profile) {
    final shippingItems = profile.listings.where((p) => p.status == 'reserved' && p.txnId != null).toList();
    
    if (shippingItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
        child: const Center(child: Text('No pending shipments', style: TextStyle(color: ecoMuted))),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shippingItems.length,
      itemBuilder: (context, i) {
        final item = shippingItems[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 50, height: 50, child: ProductImage(image: item.image))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('Buyer: ${item.buyerEmail ?? "N/A"}', style: TextStyle(color: ecoMuted, fontSize: 11)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: profile.isLoading 
                  ? null 
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await profile.markAsShipped(item.txnId!);
                      if (!mounted) return;
                      if (profile.error != null) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(profile.error!), backgroundColor: ecoError),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Item marked as shipped!'), backgroundColor: ecoGreen),
                        );
                      }
                    },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ecoGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                ),
                child: profile.isLoading 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Mark Shipped', style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewsList(ProfileProvider profile) {
    if (profile.reviews.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
        child: const Center(child: Text('No reviews yet', style: TextStyle(color: ecoMuted))),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: profile.reviews.length,
      itemBuilder: (context, i) {
        final r = profile.reviews[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(5, (index) => Icon(
                      index < r.rating ? Icons.star : Icons.star_border,
                      color: Colors.orangeAccent,
                      size: 14,
                    )),
                  ),
                  Text(r.reviewerEmail.split('@')[0], style: TextStyle(color: ecoMuted, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              Text(r.comment, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }
}

class ProductImage extends StatelessWidget {
  final String? image;
  const ProductImage({super.key, this.image});

  @override
  Widget build(BuildContext context) {
    if (image == null || image!.isEmpty) {
      return Container(color: ecoSurface, child: const Icon(Icons.image_not_supported, color: ecoMuted));
    }
    return Image.network(
      image!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(color: ecoSurface, child: const Icon(Icons.broken_image, color: ecoMuted)),
    );
  }
}
