import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/sell_provider.dart';
import '../theme/app_theme.dart';

const _categoryOptions = ['electronics', 'clothing', 'books', 'home', 'accessories', 'other'];
const _materialOptions = ['cotton', 'polyester', 'wood', 'metal', 'plastic', 'glass', 'other'];
const _conditionOptions = ['new', 'like-new', 'good', 'fair', 'poor'];

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  String _category = '';
  String _material = '';
  String _condition = '';
  String _imageBase64 = '';
  bool _hasImage = false;
  Map<String, double>? _pickedLocation;
  bool _gettingLocation = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _locationCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    final mime = xFile.mimeType ?? 'image/jpeg';
    setState(() {
      _imageBase64 = 'data:$mime;base64,${base64Encode(bytes)}';
      _hasImage = true;
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition();
        setState(() {
          _pickedLocation = {
            'lat': position.latitude,
            'lng': position.longitude,
          };
          _locationCtrl.text = "Current Location pinned 📍";
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    } finally {
      setState(() => _gettingLocation = false);
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    
    if (!auth.isLoggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please log in to list a product')),
      );
      return;
    }

    if (!_hasImage || _titleCtrl.text.isEmpty || _priceCtrl.text.isEmpty || _category.isEmpty || _material.isEmpty || _condition.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please fill in all required fields (Category, Material, Condition) and add a photo')),
      );
      return;
    }

    await context.read<SellProvider>().listProduct(CreateProductRequest(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text) ?? 0,
      badge: _condition == 'new' ? 'New' : 'Used',
      image: _imageBase64,
      category: _category,
      material: _material,
      sellerEmail: user?.email ?? '',
      sellerLocation: _locationCtrl.text.trim(),
      location: _pickedLocation,
      sellerUpiId: _upiCtrl.text.trim(),
    ));

    if (mounted && context.read<SellProvider>().success) {
      context.read<SellProvider>().reset();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌿 Item listed successfully!'),
          backgroundColor: ecoGreen,
        ),
      );
      // Clear form
      _titleCtrl.clear(); _descCtrl.clear();
      _priceCtrl.clear(); _locationCtrl.clear(); _upiCtrl.clear();
      setState(() { 
        _imageBase64 = ''; 
        _hasImage = false; 
        _category = ''; 
        _material = ''; 
        _condition = ''; 
        _pickedLocation = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final sell = context.watch<SellProvider>();
    final canSubmit = auth.isLoggedIn && 
        _hasImage && 
        _titleCtrl.text.isNotEmpty && 
        _priceCtrl.text.isNotEmpty && 
        _category.isNotEmpty && 
        _material.isNotEmpty && 
        _condition.isNotEmpty && 
        !sell.isLoading;

    return Scaffold(
      backgroundColor: ecoDark,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(gradient: ecoHeaderGradient),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('🌿 Sell an Item',
                        style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                    Text('List your eco-friendly product',
                        style: TextStyle(color: ecoMuted, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Image picker
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: ecoCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _hasImage ? ecoGreen : ecoBorder, width: _hasImage ? 2 : 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _hasImage
                        ? Stack(fit: StackFit.expand, children: [
                            Image.memory(
                              Uri.parse(_imageBase64).data!.contentAsBytes(),
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 8, right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: ecoGreen, shape: BoxShape.circle),
                                child: const Icon(Icons.check, color: Colors.white, size: 16),
                              ),
                            ),
                          ])
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.add_photo_alternate_outlined, color: ecoMuted, size: 40),
                            const SizedBox(height: 8),
                            Text('Tap to add product photo', style: TextStyle(color: ecoMuted)),
                            Text('Max 5MB · JPG, PNG, WebP',
                                style: TextStyle(color: ecoMuted.withValues(alpha: 0.7), fontSize: 11)),
                          ]),
                  ),
                ),
                const SizedBox(height: 20),

                _FormLabel('Product Name'),
                const SizedBox(height: 6),
                _EcoField(ctrl: _titleCtrl, hint: 'Enter product name', onChanged: (_) => setState(() {})),
                const SizedBox(height: 16),

                _FormLabel('Description'),
                const SizedBox(height: 6),
                _EcoField(ctrl: _descCtrl, hint: 'Describe your product', maxLines: 3),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _FormLabel('Category'),
                    const SizedBox(height: 6),
                    _EcoDropdown(value: _category, options: _categoryOptions,
                        onSelect: (v) => setState(() => _category = v)),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _FormLabel('Material'),
                    const SizedBox(height: 6),
                    _EcoDropdown(value: _material, options: _materialOptions,
                        onSelect: (v) => setState(() => _material = v)),
                  ])),
                ]),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _FormLabel('Price (₹)'),
                    const SizedBox(height: 6),
                    _EcoField(
                      ctrl: _priceCtrl, hint: '0',
                      type: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _FormLabel('Condition'),
                    const SizedBox(height: 6),
                    _EcoDropdown(value: _condition, options: _conditionOptions,
                        onSelect: (v) => setState(() => _condition = v)),
                  ])),
                ]),
                const SizedBox(height: 16),

                _FormLabel('Location'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _EcoField(ctrl: _locationCtrl, hint: 'Your city')),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _gettingLocation ? null : _getCurrentLocation,
                      style: IconButton.styleFrom(backgroundColor: ecoCard),
                      icon: _gettingLocation 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ecoGreenLight))
                        : Icon(_pickedLocation != null ? Icons.location_on : Icons.my_location, color: ecoGreenLight),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _FormLabel('UPI ID (for receiving payments)'),
                const SizedBox(height: 6),
                _EcoField(
                  ctrl: _upiCtrl,
                  hint: 'yourname@upi or 9876543210@paytm',
                ),
                Text('  💡 Buyers will pay you directly via UPI',
                    style: TextStyle(color: ecoMuted, fontSize: 11)),
                const SizedBox(height: 16),

                // Error
                if (sell.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ecoError.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('⚠️ ${sell.error}',
                        style: const TextStyle(color: ecoError, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],

                // Submit
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: canSubmit
                          ? ecoGreenGradient
                          : LinearGradient(colors: [
                              ecoGreen.withValues(alpha: 0.4),
                              ecoLeaf.withValues(alpha: 0.4)
                            ]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextButton(
                      onPressed: canSubmit ? _submit : null,
                      child: sell.isLoading
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('Listing Item...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                            ])
                          : const Text('List Item 🌿',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
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
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
  );
}

class _EcoField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final int maxLines;
  final TextInputType? type;
  final void Function(String)? onChanged;
  const _EcoField({required this.ctrl, required this.hint, this.maxLines = 1, this.type, this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: type,
    onChanged: onChanged,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: ecoMuted),
      filled: true, fillColor: ecoCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ecoBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ecoBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: ecoGreen, width: 1.5)),
    ),
  );
}

class _EcoDropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final void Function(String) onSelect;
  const _EcoDropdown({required this.value, required this.options, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: ecoCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ecoBorder),
    ),
    child: DropdownButton<String>(
      value: value.isEmpty ? null : value,
      isExpanded: true,
      dropdownColor: ecoSurface,
      underline: const SizedBox(),
      hint: Text('Select', style: TextStyle(color: ecoMuted, fontSize: 14)),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      icon: Icon(Icons.expand_more, color: ecoMuted),
      items: options.map((o) => DropdownMenuItem(
        value: o,
        child: Text(o[0].toUpperCase() + o.substring(1)),
      )).toList(),
      onChanged: (v) { if (v != null) onSelect(v); },
    ),
  );
}
