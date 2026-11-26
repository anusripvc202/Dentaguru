import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Canonical doctor consultation modes shared across Registration, Profile, and Patient UI.
class DoctorConsultationMode {
  static const String both = 'BOTH';
  static const String inPerson = 'IN_PERSON';
  static const String onlineOnly = 'ONLINE_ONLY';

  static String normalize(String? raw, {String fallback = both}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final norm = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (norm == 'ONLINE' || norm == 'ONLINE_ONLY' || norm == 'TELEMEDICINE') {
      return onlineOnly;
    }
    if (norm == 'IN_PERSON' || norm == 'CLINIC' || norm == 'CLINIC_ONLY') {
      return inPerson;
    }
    if (norm == 'BOTH' || norm == 'HYBRID' || norm == 'ALL') {
      return both;
    }
    return fallback;
  }

  static bool isOnlineOnly(String? raw) => normalize(raw) == onlineOnly;

  static bool requiresClinicDetails(String? raw) => !isOnlineOnly(raw);

  static String displayLabel(String? raw) {
    switch (normalize(raw)) {
      case onlineOnly:
        return 'Online Only';
      case inPerson:
        return 'In-Person Clinic';
      case both:
      default:
        return 'In-Person & Online';
    }
  }
}

/// Centralized OpenStreetMap configuration.
/// Production deployments can override tiles via:
/// `--dart-define=OSM_TILE_URL=https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=YOUR_KEY`
class OsmMapConfig {
  static const String defaultTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const String tileUrlTemplate = String.fromEnvironment(
    'OSM_TILE_URL',
    defaultValue: defaultTileUrl,
  );

  static const String userAgentPackageName = 'in.gshealth.app';

  static const LatLng defaultIndiaCenter = LatLng(20.5937, 78.9629);
  static const double defaultIndiaZoom = 5.0;
  static const double selectedPinZoom = 15.0;

  /// Optional test hook to avoid live HTTP tile requests during headless widget tests.
  @visibleForTesting
  static TileProvider? debugTileProviderOverride;

  static TileProvider resolveTileProvider() {
    if (debugTileProviderOverride != null) {
      return debugTileProviderOverride!;
    }
    return NetworkTileProvider();
  }
}

/// Deterministic 1x1 transparent PNG tile provider usable in tests or offline fallback.
class OfflinePlaceholderTileProvider extends TileProvider {
  static final Uint8List _transparentPng = Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_transparentPng);
  }
}

class ClinicDirectionsHelper {
  /// Optional test override to capture launched direction URIs without invoking OS channels.
  @visibleForTesting
  static Future<bool> Function(Uri uri)? debugLaunchUriOverride;

  static bool hasValidCoordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (!latitude.isFinite || !longitude.isFinite) return false;
    return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
  }

  static String composeAddressQuery({
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) {
    final parts = <String>[];
    void addUnique(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return;
      final lower = clean.toLowerCase();
      if (!parts.any((p) => p.toLowerCase() == lower || p.toLowerCase().contains(lower))) {
        parts.add(clean);
      }
    }

    addUnique(clinicName);
    addUnique(clinicAddress);
    addUnique(city);
    addUnique(state);
    addUnique(pincode);
    return parts.join(', ');
  }

  /// Builds the primary external navigation URI.
  /// - Returns `null` for Online-Only doctors or when neither coordinates nor address exist.
  /// - Uses exact coordinates when available; falls back to manual address search query otherwise.
  static Uri? buildDirectionsUri({
    required String consultationMode,
    double? latitude,
    double? longitude,
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) {
    if (DoctorConsultationMode.isOnlineOnly(consultationMode)) {
      return null;
    }
    if (hasValidCoordinates(latitude, longitude)) {
      final latStr = latitude!.toStringAsFixed(6);
      final lngStr = longitude!.toStringAsFixed(6);
      return Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent('$latStr,$lngStr')}',
      );
    }

    final query = composeAddressQuery(
      clinicName: clinicName,
      clinicAddress: clinicAddress,
      city: city,
      state: state,
      pincode: pincode,
    );
    if (query.isEmpty) return null;

    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(query)}',
    );
  }

  /// OpenStreetMap web fallback URI when coordinates or address are available.
  static Uri? buildOsmFallbackUri({
    required String consultationMode,
    double? latitude,
    double? longitude,
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) {
    if (DoctorConsultationMode.isOnlineOnly(consultationMode)) {
      return null;
    }
    if (hasValidCoordinates(latitude, longitude)) {
      final latStr = latitude!.toStringAsFixed(6);
      final lngStr = longitude!.toStringAsFixed(6);
      return Uri.parse('https://www.openstreetmap.org/?mlat=$latStr&mlon=$lngStr#map=16/$latStr/$lngStr');
    }
    final query = composeAddressQuery(
      clinicName: clinicName,
      clinicAddress: clinicAddress,
      city: city,
      state: state,
      pincode: pincode,
    );
    if (query.isEmpty) return null;
    return Uri.parse('https://www.openstreetmap.org/search?query=${Uri.encodeComponent(query)}');
  }

  static Future<bool> launchDirections({
    required BuildContext context,
    required String consultationMode,
    double? latitude,
    double? longitude,
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) async {
    final primaryUri = buildDirectionsUri(
      consultationMode: consultationMode,
      latitude: latitude,
      longitude: longitude,
      clinicName: clinicName,
      clinicAddress: clinicAddress,
      city: city,
      state: state,
      pincode: pincode,
    );
    if (primaryUri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clinic location is not available for directions.'),
            backgroundColor: AppTheme.gsNavy,
          ),
        );
      }
      return false;
    }

    final testOverride = debugLaunchUriOverride;
    if (testOverride != null) {
      return testOverride(primaryUri);
    }

    try {
      if (await launchUrl(primaryUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}

    final osmUri = buildOsmFallbackUri(
      consultationMode: consultationMode,
      latitude: latitude,
      longitude: longitude,
      clinicName: clinicName,
      clinicAddress: clinicAddress,
      city: city,
      state: state,
      pincode: pincode,
    );
    if (osmUri != null) {
      try {
        if (await launchUrl(osmUri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open maps application on this device.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
    }
    return false;
  }
}

/// Compact OpenStreetMap preview card with mandatory © OpenStreetMap contributors attribution.
class OsmLocationPreviewCard extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String title;
  final String subtitle;
  final VoidCallback? onChangeLocation;
  final VoidCallback? onRemoveLocation;
  final VoidCallback? onOpenDirections;
  final double mapHeight;

  const OsmLocationPreviewCard({
    super.key,
    required this.latitude,
    required this.longitude,
    this.title = 'Pinned Clinic Location',
    this.subtitle = '',
    this.onChangeLocation,
    this.onRemoveLocation,
    this.onOpenDirections,
    this.mapHeight = 136,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    final coordLabel = '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: OsmMapConfig.selectedPinZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: OsmMapConfig.tileUrlTemplate,
                        userAgentPackageName: OsmMapConfig.userAgentPackageName,
                        tileProvider: OsmMapConfig.resolveTileProvider(),
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppTheme.gsRed,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin_drop_rounded, size: 16, color: AppTheme.gsRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.trim().isNotEmpty ? '$subtitle ($coordLabel)' : 'Coordinates: $coordLabel',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (onChangeLocation != null || onRemoveLocation != null || onOpenDirections != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (onChangeLocation != null)
                        OutlinedButton.icon(
                          key: const Key('osm_preview_change_location_btn'),
                          onPressed: onChangeLocation,
                          icon: const Icon(Icons.edit_location_alt_outlined, size: 15),
                          label: const Text('Change Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            side: const BorderSide(color: AppTheme.gsNavy),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      if (onRemoveLocation != null)
                        TextButton.icon(
                          key: const Key('osm_preview_remove_location_btn'),
                          onPressed: onRemoveLocation,
                          icon: const Icon(Icons.location_off_outlined, size: 15),
                          label: const Text('Remove Pin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.gsRed,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                      if (onOpenDirections != null)
                        ElevatedButton.icon(
                          key: const Key('osm_preview_directions_btn'),
                          onPressed: onOpenDirections,
                          icon: const Icon(Icons.directions_rounded, size: 15),
                          label: const Text('Directions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
