import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/marketplace_provider.dart';
import 'providers/sell_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/chat_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // System UI overlay style (transparent status bar)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: ecoDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Init auth (reads persisted user from SharedPreferences)
  final auth = AuthProvider();
  await auth.init();

  runApp(EcoWaveApp(auth: auth));
}

class EcoWaveApp extends StatelessWidget {
  final AuthProvider auth;
  const EcoWaveApp({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    final marketplaceProvider = MarketplaceProvider();
    final sellProvider = SellProvider();

    // Wire up cross-provider cache invalidation
    sellProvider.onProductListed = () => marketplaceProvider.invalidateCache();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: marketplaceProvider),
        ChangeNotifierProvider.value(value: sellProvider),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Builder(builder: (context) {
        final router = AppRouter.build(context.read<AuthProvider>());
        return MaterialApp.router(
          title: 'EcoWave',
          debugShowCheckedModeBanner: false,
          theme: buildEcoTheme(),
          routerConfig: router,
        );
      }),
    );
  }
}
