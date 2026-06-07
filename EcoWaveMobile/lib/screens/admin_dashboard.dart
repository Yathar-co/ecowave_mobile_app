import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../config/server_config.dart';
import '../providers/auth_provider.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _reports = [];
  List<dynamic> _products = [];
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  String? _errorMessage;

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await Future.wait([
        _loadReports(),
        _loadProducts(),
        _loadUsers(),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().contains('403') 
            ? 'Unauthorized: Admin access only' 
            : 'Connection Error: Check if backend is running');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Dio get _dio {
    final token = context.read<AuthProvider>().user?.token;
    return Dio(BaseOptions(
      baseUrl: serverUrl,
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ));
  }

  Future<void> _loadReports() async {
    final res = await _dio.get('/api/admin/reports');
    if (mounted) setState(() => _reports = res.data['reports'] as List<dynamic>);
  }

  Future<void> _loadProducts() async {
    final res = await _dio.get('/api/admin/products');
    if (mounted) setState(() => _products = res.data['products'] as List<dynamic>);
  }

  Future<void> _loadUsers() async {
    final res = await _dio.get('/api/admin/users');
    if (mounted) {
      setState(() {
        // Handle potential {success: true, users: [...]} structure
        final data = res.data;
        if (data is Map && data.containsKey('users')) {
          _users = data['users'] as List<dynamic>;
        } else {
          _users = res.data as List<dynamic>;
        }
      });
    }
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ecoDark,
      appBar: AppBar(
        backgroundColor: ecoSurface,
        elevation: 0,
        title: Row(
          children: [
            const Text('🌊', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            const Text('Admin Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh, color: ecoGreenLight)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout, color: ecoError)),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ecoGreen,
          isScrollable: true,
          labelColor: ecoGreenLight,
          unselectedLabelColor: ecoMuted,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: 'Reports', icon: Icon(Icons.report_problem_outlined)),
            Tab(text: 'Products', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'Users', icon: Icon(Icons.people_outline)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ecoGreen))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: ecoError, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                      TextButton(onPressed: _loadAll, child: const Text('Retry', style: TextStyle(color: ecoGreen))),
                    ],
                  ),
                )
              : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildReportsTab(),
                _buildProductsTab(),
                _buildUsersTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('System Summary', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
            children: [
              _statCard('Total Users', _users.length.toString(), Icons.people, Colors.blue),
              _statCard('Active Products', _products.where((p) => p['status'] == 'active').length.toString(), Icons.shopping_bag, Colors.orange),
              _statCard('Pending Reports', _reports.length.toString(), Icons.warning, Colors.red),
              _statCard('Verified Sellers', _users.where((u) => u['is_verified'] == true).length.toString(), Icons.verified, Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ecoBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(color: ecoMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    if (_reports.isEmpty) return const Center(child: Text('No pending reports', style: TextStyle(color: ecoMuted)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (context, i) {
        final r = _reports[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: ecoBorder)),
          child: ListTile(
            title: Text(r['reason'].toString().toUpperCase(), style: const TextStyle(color: ecoError, fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('Target: ${r['target_id']}\n${r['description']}', style: TextStyle(color: ecoMuted, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.check_circle_outline, color: ecoGreen),
              onPressed: () => _dio.post('/api/admin/dismiss-report/${r['report_id']}').then((_) => _loadReports()),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _products.length,
      itemBuilder: (context, i) {
        final p = _products[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: ecoCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: ecoBorder)),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: ecoSurface, child: Text('📦', style: TextStyle(fontSize: 14))),
            title: Text(p['title'], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: Text('₹${p['price']} • Status: ${p['status']}', style: TextStyle(color: ecoMuted, fontSize: 12)),
            trailing: PopupMenuButton<String>(
              onSelected: (val) => _dio.post('/api/admin/products/${p['id']}/status', data: {'status': val}).then((_) => _loadProducts()),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'active', child: Text('Active')),
                const PopupMenuItem(value: 'under_review', child: Text('Under Review')),
                const PopupMenuItem(value: 'banned', child: Text('Ban Item')),
              ],
              icon: const Icon(Icons.more_vert, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    if (_users.isEmpty) return const Center(child: Text('No users found', style: TextStyle(color: ecoMuted)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, i) {
        final u = _users[i];
        final isVerified = u['is_verified'] == true;
        final isBanned = u['is_banned'] == true;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: ecoCard, 
            borderRadius: BorderRadius.circular(12), 
            border: Border.all(color: isBanned ? ecoError.withValues(alpha: 0.5) : ecoBorder)
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isBanned ? ecoError.withValues(alpha: 0.2) : ecoSurface,
              child: Text(u['name'][0].toUpperCase(), style: TextStyle(color: isBanned ? ecoError : ecoGreen))
            ),
            title: Row(
              children: [
                Expanded(child: Text(u['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                if (isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, color: ecoGreen, size: 14)),
                if (isBanned) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.block, color: ecoError, size: 14)),
              ],
            ),
            subtitle: Text(u['email'], style: TextStyle(color: ecoMuted, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.inventory_2_outlined, color: Colors.blue, size: 20),
                  tooltip: 'View Items',
                  onPressed: () => _showUserProducts(u['email']),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'verify') {
                      _dio.post('/api/admin/users/${u['email']}/verify', data: {'is_verified': !isVerified}).then((_) => _loadUsers());
                    } else if (val == 'ban') {
                      _dio.post('/api/admin/users/${u['email']}/ban', data: {'is_banned': !isBanned}).then((_) => _loadUsers());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'verify', child: Text(isVerified ? 'Unverify User' : 'Verify User')),
                    PopupMenuItem(value: 'ban', child: Text(isBanned ? 'Unban User' : 'Ban User')),
                  ],
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUserProducts(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ecoSurface,
        title: Text('Items by $email', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<Response>(
            future: _dio.get('/api/products/seller/$email'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final products = (snapshot.data?.data['products'] as List? ?? []);
              if (products.isEmpty) return const Text('No items listed', style: TextStyle(color: ecoMuted));
              return ListView.builder(
                shrinkWrap: true,
                itemCount: products.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(products[i]['title'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text('₹${products[i]['price']}', style: const TextStyle(color: ecoGreenLight, fontSize: 11)),
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}
