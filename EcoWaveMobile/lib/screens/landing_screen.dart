import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ecoDark,
      body: Stack(
        children: [
          // Top gradient
          Container(
            height: MediaQuery.of(context).size.height * 0.55,
            decoration: BoxDecoration(gradient: ecoHeaderGradient),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // Hero section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Text('🌊', style: TextStyle(fontSize: 80)),
                      const SizedBox(height: 16),
                      const Text(
                        'EcoWave',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Buy & sell sustainable goods.\nJoin the eco-movement.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ecoMuted,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Stats row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatChip('🌿', '25k+', 'kg CO₂ saved'),
                          _StatChip('♻️', '10k+', 'items listed'),
                          _StatChip('💧', '500k+', 'litres saved'),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // CTA buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Get Started
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: ecoGreenGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextButton(
                            onPressed: () => context.push('/register'),
                            child: const Text(
                              'Get Started 🌱',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Login
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: ecoBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => context.push('/login'),
                          child: Text(
                            'I already have an account',
                            style: TextStyle(color: ecoMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _StatChip(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ecoCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ecoBorder),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: ecoGreenLight,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          Text(label, style: TextStyle(color: ecoMuted, fontSize: 10)),
        ],
      ),
    );
  }
}
