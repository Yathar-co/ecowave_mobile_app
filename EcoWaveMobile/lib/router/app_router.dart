import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/landing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/sell_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/chats_list_screen.dart';
import '../screens/map_screen.dart';
import '../screens/admin_dashboard.dart';
import '../screens/seller_dashboard.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class AppRouter {
  static GoRouter build(AuthProvider auth) => GoRouter(
        initialLocation: auth.isLoggedIn 
            ? (auth.user?.email == 'admin@ecowave.com' ? '/admin' : '/marketplace') 
            : '/landing',
        redirect: (context, state) {
          final user = context.read<AuthProvider>().user;
          final loggedIn = user != null;
          final isAdmin = user?.email == 'admin@ecowave.com';

          // Redirect Admin to dashboard if they try to access regular user screens
          if (isAdmin && (state.matchedLocation == '/marketplace' || state.matchedLocation == '/sell' || state.matchedLocation == '/profile')) {
            return '/admin';
          }

          // Protect routes
          final protected = ['/sell', '/profile', '/messages', '/admin'];
          if (!loggedIn && protected.contains(state.matchedLocation)) {
            return '/login';
          }

          // Protect admin route from non-admins
          if (state.matchedLocation == '/admin' && !isAdmin) {
            return '/marketplace';
          }

          return null;
        },
        routes: [
          GoRoute(
            path: '/landing',
            builder: (_, __) => const LandingScreen(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const LoginScreen(),
          ),
          GoRoute(
            path: '/register',
            builder: (_, __) => const RegisterScreen(),
          ),
          ShellRoute(
            builder: (context, state, child) => _MainShell(child: child),
            routes: [
              GoRoute(
                path: '/marketplace',
                builder: (_, __) => const MarketplaceScreen(),
              ),
              GoRoute(
                path: '/sell',
                builder: (_, __) => const SellScreen(),
              ),
              GoRoute(
                path: '/messages',
                builder: (_, __) => const ChatsListScreen(),
              ),
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) {
              final extra = state.extra;
              if (extra is Product) {
                return ChatScreen(product: extra);
              }
              final map = extra as Map<String, dynamic>;
              return ChatScreen(
                product: map['product'] as Product,
                buyerEmail: map['buyerEmail'] as String?,
              );
            },
          ),
          GoRoute(
            path: '/map',
            builder: (context, state) => MapScreen(product: state.extra as Product),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminDashboard(),
          ),
          GoRoute(
            path: '/seller-dashboard',
            builder: (context, state) => const SellerDashboard(),
          ),
        ],
      );
}

class _MainShell extends StatelessWidget {
  final Widget child;
  const _MainShell({required this.child});

  int _indexFor(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/sell')) return 1;
    if (loc.startsWith('/messages')) return 2;
    if (loc.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _indexFor(context);
    return Scaffold(
      backgroundColor: ecoDark,
      body: child,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            backgroundColor: ecoSurface,
            indicatorColor: ecoGreen.withValues(alpha: 0.2),
            selectedIndex: idx,
            onDestinationSelected: (i) {
              switch (i) {
                case 0:
                  context.go('/marketplace');
                case 1:
                  context.go('/sell');
                case 2:
                  context.go('/messages');
                case 3:
                  context.go('/profile');
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.store_outlined),
                selectedIcon: Icon(Icons.store, color: ecoGreenLight),
                label: 'Explore',
              ),
              NavigationDestination(
                icon: Icon(Icons.add_circle_outline),
                selectedIcon: Icon(Icons.add_circle, color: ecoGreenLight),
                label: 'Sell',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble, color: ecoGreenLight),
                label: 'Messages',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: ecoGreenLight),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
