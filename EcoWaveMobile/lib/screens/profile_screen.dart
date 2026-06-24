import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../screens/marketplace_screen.dart';
import '../screens/bill_dialog.dart';
import '../screens/report_dialog.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.user != null) {
        auth.refreshProfile(); // Get latest stats and badges
        context.read<ProfileProvider>().load(auth.user!.email);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final profile = context.watch<ProfileProvider>();

    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: ecoDark,
      body: CustomScrollView(
        slivers: [
          // ── App header ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(gradient: ecoHeaderGradient),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('👤 My Profile',
                          style: TextStyle(
                              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                      // Logout
                      TextButton.icon(
                        onPressed: () {
                          context.read<AuthProvider>().logout();
                          context.go('/landing');
                        },
                        icon: Icon(Icons.logout, color: ecoMuted, size: 18),
                        label: Text('Logout', style: TextStyle(color: ecoMuted, fontSize: 13)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ]),
                    
                    if (user.email == 'admin@ecowave.com') ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => context.push('/admin'),
                        icon: const Icon(Icons.admin_panel_settings, color: ecoGreenLight, size: 18),
                        label: const Text('Admin Dashboard', style: TextStyle(color: ecoGreenLight, fontSize: 13)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ] else if (profile.listings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => context.push('/seller-dashboard'),
                        icon: const Icon(Icons.dashboard, color: ecoGreenLight, size: 18),
                        label: const Text('Seller Dashboard', style: TextStyle(color: ecoGreenLight, fontSize: 13)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Avatar + name
                    Row(children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          gradient: ecoGreenGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(
                          children: [
                            Text(user.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            if (user.isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, color: ecoGreen, size: 16),
                            ],
                          ],
                        ),
                        Text(user.email,
                            style: TextStyle(color: ecoMuted, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ])),
                    ]),
                  ]),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Eco impact stats ─────────────────────────────────────
                const Text('🌍 Your Eco Impact',
                    style: TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _ImpactGrid(stats: profile.impactStats),
                const SizedBox(height: 28),

                // ── My listings ──────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('📦 My Listings',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${profile.listings.length} items',
                      style: TextStyle(color: ecoMuted, fontSize: 12)),
                ]),
                const SizedBox(height: 12),

                if (profile.isLoading)
                  const Center(child: CircularProgressIndicator(color: ecoGreen))
                else if (profile.listings.isEmpty)
                  _EmptyListings()
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: profile.listings.length,
                    itemBuilder: (_, i) => _ListingCard(
                      product: profile.listings[i],
                      onMarkShipped: () => profile.markAsShipped(profile.listings[i].txnId ?? ''),
                      onDelete: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => _DeleteDialog(
                              title: profile.listings[i].title),
                        );
                        if (ok == true && mounted) {
                          profile.deleteListing(profile.listings[i].id);
                        }
                      },
                    ),
                  ),

                const SizedBox(height: 32),

                // ── My Purchases ─────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('🛍️ My Purchases',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${profile.purchases.length} items',
                      style: TextStyle(color: ecoMuted, fontSize: 12)),
                ]),
                const SizedBox(height: 12),

                if (profile.isLoading)
                  const Center(child: CircularProgressIndicator(color: ecoGreen))
                else if (profile.purchases.isEmpty)
                  _EmptyPurchases()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: profile.purchases.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _PurchaseCard(
                      product: profile.purchases[i],
                      onReview: () => _showReviewDialog(context, profile.purchases[i]),
                      onViewBill: () => _showBill(context, profile.purchases[i].txnId),
                      onReport: () => showDialog(
                        context: context,
                        builder: (_) => ReportDialog(
                          targetId: profile.purchases[i].id,
                          targetType: 'product',
                          targetName: profile.purchases[i].title,
                          txnId: profile.purchases[i].txnId,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showBill(BuildContext context, String? txnId) {
    if (txnId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill not available for this transaction'), backgroundColor: ecoError),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => BillDialog(txnId: txnId),
    );
  }

  void _showReviewDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (_) => _ReviewDialog(product: product),
    );
  }
}

// ── Eco Impact Grid ───────────────────────────────────────────────────────────

class _ImpactGrid extends StatelessWidget {
  final ImpactStats? stats;
  const _ImpactGrid({this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.6,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _StatCard('🌿', 'CO₂ Saved', s != null ? '${s.co2Saved.toStringAsFixed(1)} kg' : '0 kg'),
        _StatCard('💧', 'Water Saved', s != null ? '${s.waterSaved.toStringAsFixed(0)}L' : '0L'),
        _StatCard('♻️', 'Items Recycled', s != null ? '${s.itemsRecycled}' : '0'),
        _StatCard('🛍️', 'Items Bought', s != null ? '${s.itemsPurchased}' : '0'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji, label, value;
  const _StatCard(this.emoji, this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ecoCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ecoBorder),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const Spacer(),
      Text(value,
          style: const TextStyle(
              color: ecoGreenLight, fontWeight: FontWeight.w800, fontSize: 18)),
      Text(label, style: TextStyle(color: ecoMuted, fontSize: 11)),
    ]),
  );
}

// ── Listing Card ──────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  final Product product;
  final VoidCallback onDelete;
  final VoidCallback onMarkShipped;
  const _ListingCard({required this.product, required this.onDelete, required this.onMarkShipped});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: ecoCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ecoBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 5,
        child: Stack(fit: StackFit.expand, children: [
          ProductImage(image: product.image),
          // Status badge
          Positioned(
            top: 6, left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: product.status == 'sold'
                    ? ecoMuted.withValues(alpha: 0.8)
                    : product.status == 'reserved' ? Colors.orange.withValues(alpha: 0.9) : ecoLeaf.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                product.status.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // Delete button
          Positioned(
            top: 6, right: 6,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: ecoError.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 12),
              ),
            ),
          ),
        ]),
      ),
      Flexible(
        flex: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
            Text(product.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('₹${product.price.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: ecoGreenLight, fontWeight: FontWeight.w700, fontSize: 13)),
            if (product.status == 'reserved' && product.txnId != null) ...[
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 24,
                child: ElevatedButton(
                  onPressed: onMarkShipped,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ecoGreen,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('Mark Shipped', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ]),
        ),
      ),
    ]),
  );
}

// ── Empty Listings ────────────────────────────────────────────────────────────

class _EmptyListings extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: ecoCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ecoBorder),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🌱', style: TextStyle(fontSize: 40)),
      const SizedBox(height: 8),
      const Text('No listings yet',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('List your first eco-product!', style: TextStyle(color: ecoMuted, fontSize: 13)),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: ecoGreenGradient, borderRadius: BorderRadius.circular(12)),
          child: TextButton(
            onPressed: () => context.go('/sell'),
            child: const Text('Sell an Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ]),
  );
}

// ── Purchase Card ──────────────────────────────────────────────────────────────

class _PurchaseCard extends StatelessWidget {
  final Product product;
  final VoidCallback onReview;
  final VoidCallback onViewBill;
  final VoidCallback onReport;
  const _PurchaseCard({
    required this.product,
    required this.onReview,
    required this.onViewBill,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ecoCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ecoBorder),
    ),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 65, height: 65,
          child: ProductImage(image: product.image),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(product.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        Text('Sold by ${product.sellerEmail}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ecoMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text('₹${product.price.toStringAsFixed(0)}',
            style: const TextStyle(
                color: ecoGreenLight, fontWeight: FontWeight.w800, fontSize: 16)),
      ])),
      const SizedBox(width: 8),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: onReview,
            style: ElevatedButton.styleFrom(
              backgroundColor: ecoLeaf.withValues(alpha: 0.1),
              foregroundColor: ecoGreenLight,
              elevation: 0,
              side: const BorderSide(color: ecoLeaf, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(80, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: onViewBill,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: ecoBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(80, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Bill', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: onReport,
            style: OutlinedButton.styleFrom(
              foregroundColor: ecoError,
              side: BorderSide(color: ecoError.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(80, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ecoError)),
          ),
        ],
      ),
    ]),
  );
}

// ── Empty Purchases ───────────────────────────────────────────────────────────

class _EmptyPurchases extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: ecoCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ecoBorder),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🛒', style: TextStyle(fontSize: 40)),
      const SizedBox(height: 8),
      const Text('No purchases yet',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Find sustainable treasures!', style: TextStyle(color: ecoMuted, fontSize: 13)),
    ]),
  );
}

// ── Review Dialog ─────────────────────────────────────────────────────────────

class _ReviewDialog extends StatefulWidget {
  final Product product;
  const _ReviewDialog({required this.product});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  double _rating = 5.0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await context.read<ProfileProvider>().addReview(
        productId: widget.product.id,
        rating: _rating,
        comment: _commentCtrl.text,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your review!'), backgroundColor: ecoGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: ecoError),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ecoSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Write a Review',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(widget.product.title,
                style: TextStyle(color: ecoMuted, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  onPressed: () => setState(() => _rating = index + 1.0),
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.orangeAccent,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                hintStyle: TextStyle(color: ecoMuted),
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: ecoMuted)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ecoGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Delete Confirmation ───────────────────────────────────────────────────────

class _DeleteDialog extends StatelessWidget {
  final String title;
  const _DeleteDialog({required this.title});

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: ecoSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('Delete Listing', style: TextStyle(color: Colors.white)),
    content: Text('Remove "$title" from your listings?',
        style: TextStyle(color: ecoMuted)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text('Cancel', style: TextStyle(color: ecoMuted)),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Delete', style: TextStyle(color: ecoError)),
      ),
    ],
  );
}
