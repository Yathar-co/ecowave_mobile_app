import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ecoGreen,
        icon: const Icon(Icons.directions, color: Colors.white),
        label: const Text('Open Directions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => _openDirections(context, location['lat']!, location['lng']!),
      ),
    );
  }

  Future<void> _openDirections(BuildContext context, double lat, double lng) async {
    // Try Google Maps first, then fall back to generic geo URI
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    
    try {
      final launched = await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        // Fallback: try generic geo URI (works with any maps app)
        final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
        await launchUrl(geoUri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open maps: $e'), backgroundColor: ecoError),
        );
      }
    }
  }
}
