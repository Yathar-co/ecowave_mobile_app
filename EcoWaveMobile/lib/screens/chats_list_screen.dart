import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'marketplace_screen.dart' show ProductImage;

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final convs = await ApiService().getConversations();
      setState(() => _conversations = convs);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: ecoDark,
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(gradient: ecoHeaderGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Messages',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    if (!_loading)
                      IconButton(
                        icon: const Icon(Icons.refresh, color: ecoGreenLight),
                        onPressed: _load,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(user)),
        ],
      ),
    );
  }

  Widget _buildBody(User? user) {
    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_outline, color: ecoMuted, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Sign in to view your messages',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Chat with sellers or buyers about listings',
                style: TextStyle(color: ecoMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: ecoGreenGradient,
                      borderRadius: BorderRadius.circular(12)),
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign In',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: ecoGreen));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: ecoError, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: ecoGreen),
                onPressed: _load,
                child: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum_outlined, color: ecoMuted, size: 64),
              const SizedBox(height: 16),
              const Text(
                'No conversations yet',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Open a listing and tap "Message Seller" to start chatting',
                style: TextStyle(color: ecoMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: ecoGreen),
                    foregroundColor: ecoGreenLight),
                onPressed: () => context.go('/marketplace'),
                icon: const Icon(Icons.store_outlined, size: 16),
                label: const Text('Browse Listings'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: ecoGreen,
      backgroundColor: ecoCard,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _conversations.length,
        separatorBuilder: (_, __) =>
            Divider(color: ecoBorder, height: 1, indent: 76),
        itemBuilder: (_, i) => _ConversationTile(
          conv: _conversations[i],
          currentUserEmail: user.email,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conv;
  final String currentUserEmail;

  const _ConversationTile(
      {required this.conv, required this.currentUserEmail});

  @override
  Widget build(BuildContext context) {
    final productTitle = conv['product_title'] as String? ?? 'Unknown Product';
    final lastMsg = conv['last_message'] as String? ?? '';
    final lastMsgSender = conv['last_message_sender'] as String? ?? '';
    final isSeller = conv['is_seller'] as bool? ?? false;
    final otherParty = conv['other_party'] as String? ?? '';
    final buyerEmail = conv['buyer_email'] as String?;
    final isMe = lastMsgSender == currentUserEmail;

    final product = Product(
      id: conv['product_id'] as String? ?? '',
      title: productTitle,
      image: conv['product_image'] as String? ?? '',
      sellerEmail: conv['seller_email'] as String? ?? '',
    );

    final otherName = otherParty.contains('@')
        ? otherParty.split('@').first
        : otherParty;
    final roleLabel = isSeller ? 'Buyer: $otherName' : 'Seller: $otherName';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 52,
          height: 52,
          child: ProductImage(image: product.image),
        ),
      ),
      title: Text(
        productTitle,
        style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(roleLabel,
              style:
                  const TextStyle(color: ecoGreenLight, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            isMe ? 'You: $lastMsg' : lastMsg,
            style: TextStyle(color: ecoMuted, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: ecoMuted),
      tileColor: ecoCard,
      onTap: () => context.push(
        '/chat',
        extra: <String, dynamic>{
          'product': product,
          'buyerEmail': isSeller ? buyerEmail : null,
        },
      ),
    );
  }
}
