import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

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

  /// Neutral country-level framing when no clinic pin has been selected yet (never saved as clinic coords).
  static const LatLng defaultViewportCenter = LatLng(20.5937, 78.9629);
  static const double defaultViewportZoom = 4.8;
  static const double selectedPinZoom = 15.0;

  /// Optional test hook to avoid live HTTP tile requests during headless widget tests.
  @visibleForTesting
  static TileProvider? debugTileProviderOverride;

  /// Optional test hook to simulate OpenStreetMap tile/network failure gracefully.
  @visibleForTesting
  static bool debugSimulateNetworkError = false;

  static bool get shouldSimulateNetworkError => debugSimulateNetworkError;

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

  static bool isValidPincode(String? pincode) {
    if (pincode == null) return false;
    return RegExp(r'^\d{6}$').hasMatch(pincode.trim());
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

  /// Builds the primary Google Maps directions URI.
  /// - Uses exact coordinates when valid latitude & longitude are saved.
  /// - Falls back to the saved clinic address when coordinates are unavailable for an existing doctor.
  /// - Returns `null` when neither coordinates nor clinic address exist (never fabricates fake coords).
  static Uri? buildDirectionsUri({
    double? latitude,
    double? longitude,
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) {
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
    double? latitude,
    double? longitude,
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) {
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
    double? latitude,
    double? longitude,
    String clinicName = '',
    String clinicAddress = '',
    String city = '',
    String state = '',
    String pincode = '',
  }) async {
    final primaryUri = buildDirectionsUri(
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

/// Compact OpenStreetMap preview card with mandatory © OpenStreetMap contributors attribution
/// and graceful network/tile error fallback.
class OsmLocationPreviewCard extends StatefulWidget {
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
    this.title = 'Selected Clinic Location',
    this.subtitle = '',
    this.onChangeLocation,
    this.onRemoveLocation,
    this.onOpenDirections,
    this.mapHeight = 136,
  });

  @override
  State<OsmLocationPreviewCard> createState() => _OsmLocationPreviewCardState();
}

class _OsmLocationPreviewCardState extends State<OsmLocationPreviewCard> {
  bool _tileLoadError = false;

  @override
  void initState() {
    super.initState();
    _tileLoadError = OsmMapConfig.debugSimulateNetworkError;
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.latitude, widget.longitude);
    final coordLabel =
        'Lat: ${widget.latitude.toStringAsFixed(5)}, Lng: ${widget.longitude.toStringAsFixed(5)}';

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
            height: widget.mapHeight,
            child: Stack(
              children: [
                if (_tileLoadError)
                  Container(
                    key: const Key('osm_preview_network_fallback'),
                    color: const Color(0xFFE2E8F0),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 22, color: Color(0xFF475569)),
                        SizedBox(height: 4),
                        Text(
                          'Map preview unavailable offline. Coordinates saved.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  )
                else
                  IgnorePointer(
                    child: FlutterMap(
                      key: ValueKey('osm_preview_${widget.latitude}_${widget.longitude}'),
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
                          errorTileCallback: (_, __, ___) {
                            if (mounted && !_tileLoadError) {
                              setState(() => _tileLoadError = true);
                            }
                          },
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 40,
                              height: 40,
                              alignment: Alignment.topCenter,
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
                        widget.title,
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
                  widget.subtitle.trim().isNotEmpty ? '${widget.subtitle} • $coordLabel' : coordLabel,
                  key: const Key('osm_preview_coords_text'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.onChangeLocation != null ||
                    widget.onRemoveLocation != null ||
                    widget.onOpenDirections != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (widget.onChangeLocation != null)
                        OutlinedButton.icon(
                          key: const Key('osm_preview_change_location_btn'),
                          onPressed: widget.onChangeLocation,
                          icon: const Icon(Icons.edit_location_alt_outlined, size: 15),
                          label: const Text(
                            'Change Location',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            side: const BorderSide(color: AppTheme.gsNavy),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      if (widget.onRemoveLocation != null)
                        TextButton.icon(
                          key: const Key('osm_preview_remove_location_btn'),
                          onPressed: widget.onRemoveLocation,
                          icon: const Icon(Icons.location_off_outlined, size: 15),
                          label: const Text(
                            'Remove Pin',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.gsRed,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                      if (widget.onOpenDirections != null)
                        ElevatedButton.icon(
                          key: const Key('osm_preview_directions_btn'),
                          onPressed: widget.onOpenDirections,
                          icon: const Icon(Icons.directions_rounded, size: 15),
                          label: const Text(
                            'Get Directions',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
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
