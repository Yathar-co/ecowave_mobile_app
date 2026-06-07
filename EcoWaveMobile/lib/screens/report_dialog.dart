import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ReportDialog extends StatefulWidget {
  final String targetId;
  final String targetType;
  final String targetName;

  const ReportDialog({
    super.key,
    required this.targetId,
    required this.targetType,
    required this.targetName,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _selectedReason;
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  final List<String> _reasons = [
    'Scam',
    'Fake product',
    'Spam',
    'Harassment',
    'Misleading listing',
    'Inappropriate content',
    'Other'
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;

    setState(() => _submitting = true);
    try {
      await ApiService().submitReport(
        targetId: widget.targetId,
        targetType: widget.targetType,
        reason: _selectedReason!,
        description: _descCtrl.text,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. We will review it shortly.'),
            backgroundColor: ecoGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString().replaceAll('Exception: ', '');
        if (msg.contains('initiating a purchase')) {
          msg = 'You can only report a seller or product after initiating a purchase.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: ecoError,
          ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report ${widget.targetType == 'user' ? 'Seller' : 'Product'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.targetName,
              style: TextStyle(color: ecoMuted, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            const Text(
              'Reason for reporting',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: ecoCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ecoBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedReason,
                  hint: Text('Select a reason', style: TextStyle(color: ecoMuted, fontSize: 14)),
                  dropdownColor: ecoCard,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: ecoGreen),
                  items: _reasons.map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedReason = v),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Additional details (optional)',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Describe the issue...',
                hintStyle: TextStyle(color: ecoMuted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: ecoMuted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedReason == null || _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ecoError,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
