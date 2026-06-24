import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class BillDialog extends StatelessWidget {
  final String txnId;
  const BillDialog({super.key, required this.txnId});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ecoSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: FutureBuilder<Map<String, dynamic>>(
        future: ApiService().getBill(txnId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: ecoGreen)));
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 16),
                  const Text('Failed to load bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: ecoGreenLight))),
                ],
              ),
            );
          }

          final rawData = snapshot.data!;
          // Support both nested 'bill' key and direct transaction map
          final Map<String, dynamic> bill = rawData.containsKey('bill') ? Map<String, dynamic>.from(rawData['bill']) : rawData;
          final Map snap = (bill['product_snapshot'] as Map?) ?? {};

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('INVOICE', style: TextStyle(color: ecoGreenLight, fontWeight: FontWeight.w900, fontSize: 24)),
                  const Text('🌊', style: TextStyle(fontSize: 24)),
                ]),
                const Divider(color: ecoBorder, height: 32),
                
                _billRow('Transaction ID', bill['txn_id']?.toString() ?? 'N/A'),
                _billRow('Date', (bill['created_at']?.toString() ?? '').split('T')[0]),
                _billRow('Stage', (bill['current_stage']?.toString() ?? 'unknown').toUpperCase(), color: ecoGreenLight),
                _billRow('Status', (bill['status']?.toString() ?? 'unknown').toUpperCase().replaceAll('_', ' ')),
                
                const SizedBox(height: 24),
                const Text('PRODUCT DETAILS', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Text(snap['title']?.toString() ?? 'Product', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 4),
                Text(snap['category']?.toString() ?? 'General', style: TextStyle(color: ecoMuted, fontSize: 13)),
                
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: ecoBorder)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Item Price', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('₹${bill['item_price'] ?? bill['total_amount'] ?? 0}', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Shipping Charge (3%)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('₹${bill['shipping_charge'] ?? 0}', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('↳ 1% Seller Aid', style: TextStyle(color: ecoMuted, fontSize: 11)),
                            Text('₹${bill['seller_shipping_aid'] ?? 0}', style: TextStyle(color: ecoMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('↳ 2% Carbon Offset (NGO)', style: TextStyle(color: ecoMuted, fontSize: 11)),
                            Text('₹${bill['ngo_contribution'] ?? 0}', style: TextStyle(color: ecoMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Divider(color: ecoBorder, height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Paid Amount', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('₹${bill['paid_amount'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          Text('₹${bill['total_amount'] ?? 0}', style: const TextStyle(color: ecoGreenLight, fontWeight: FontWeight.w900, fontSize: 20)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                Text('Seller: ${snap['seller_email'] ?? 'Unknown'}', style: TextStyle(color: ecoMuted, fontSize: 11)),
                Text('Buyer: ${bill['buyer_email'] ?? 'Unknown'}', style: TextStyle(color: ecoMuted, fontSize: 11)),
                
                const SizedBox(height: 32),
                if (bill['current_stage'] == 'received_confirmation_pending') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await ApiService().confirmDelivery(bill['txn_id']);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: ecoGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Confirm Delivery & Release Funds', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () async {
                         final reason = await _showDisputeDialog(context);
                         if (reason != null) {
                            try {
                              await ApiService().disputeTransaction(bill['txn_id'], reason);
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                              }
                            }
                         }
                      },
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: ecoError), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Raise Dispute / Refund', style: TextStyle(color: ecoError)),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: ecoGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _showDisputeDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ecoSurface,
        title: const Text('Raise Dispute', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Reason for dispute...', hintStyle: TextStyle(color: Colors.grey)),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(context, ctrl.text.trim());
            },
            child: const Text('Submit', style: TextStyle(color: ecoError)),
          ),
        ],
      ),
    );
  }

  Widget _billRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: ecoMuted, fontSize: 13)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
