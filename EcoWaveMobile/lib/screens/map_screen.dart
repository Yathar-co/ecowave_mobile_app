import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class MapScreen extends StatelessWidget {
  final Product product;
  const MapScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final location = product.location;
    if (location == null) {
      return Scaffold(
        backgroundColor: ecoDark,
        appBar: AppBar(
          backgroundColor: ecoSurface,
          title: const Text('Location Not Available'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📍', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('This item does not have a location set.',
                  style: TextStyle(color: ecoMuted, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    final pos = LatLng(location['lat']!, location['lng']!);

    return Scaffold(
      backgroundColor: ecoDark,
      appBar: AppBar(
        backgroundColor: ecoSurface,
        title: Text(product.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: pos,
          initialZoom: 15,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.ecowave.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: pos,
                width: 200,
                height: 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: ecoGreen,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: ecoGreen.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Text(
                        product.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.location_on,
                        color: ecoGreen, size: 32),
                  ],
                ),
              ),
            ],
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
    );
  }
}
