import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/clinic_directions_helper.dart';

/// Result returned when a doctor/clinic selects a clinic location on OpenStreetMap.
class MapLocationSelectionResult {
  final String address;
  final String city;
  final String state;
  final String pincode;
  final double latitude;
  final double longitude;
  final String locationName;

  const MapLocationSelectionResult({
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    required this.latitude,
    required this.longitude,
    required this.locationName,
  });
}

class MapLocationPickerDialog extends StatefulWidget {
  final String initialAddress;
  final String initialCity;
  final String initialState;
  final String initialPincode;
  final double? initialLat;
  final double? initialLng;
  final bool isDentist;
  final Function(
    String address,
    String city,
    String pincode,
    double lat,
    double lng,
    String locationName,
  )? onLocationSelected;
  final Function(MapLocationSelectionResult result)? onSelectionConfirmed;

  /// Optional test hook to mock OpenStreetMap Nominatim place search in tests.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function(String query)? debugSearchOverride;

  const MapLocationPickerDialog({
    super.key,
    required this.initialAddress,
    required this.initialCity,
    this.initialState = '',
    required this.initialPincode,
    this.initialLat,
    this.initialLng,
    this.isDentist = true,
    this.onLocationSelected,
    this.onSelectionConfirmed,
  });

  static Future<MapLocationSelectionResult?> show({
    required BuildContext context,
    required String initialAddress,
    required String initialCity,
    String initialState = '',
    required String initialPincode,
    double? initialLat,
    double? initialLng,
    bool isDentist = true,
    Function(
      String address,
      String city,
      String pincode,
      double lat,
      double lng,
      String locationName,
    )? onLocationSelected,
    Function(MapLocationSelectionResult result)? onSelectionConfirmed,
  }) {
    return showDialog<MapLocationSelectionResult>(
      context: context,
      builder: (ctx) => MapLocationPickerDialog(
        initialAddress: initialAddress,
        initialCity: initialCity,
        initialState: initialState,
        initialPincode: initialPincode,
        initialLat: initialLat,
        initialLng: initialLng,
        isDentist: isDentist,
        onLocationSelected: onLocationSelected,
        onSelectionConfirmed: onSelectionConfirmed,
      ),
    );
  }

  @override
  State<MapLocationPickerDialog> createState() => _MapLocationPickerDialogState();
}

class _MapLocationPickerDialogState extends State<MapLocationPickerDialog> {
  final GlobalKey _mapContainerKey = GlobalKey();
  final MapController _mapController = MapController();
  final _searchController = TextEditingController();
  final _customAddressController = TextEditingController();
  final _customCityController = TextEditingController();
  final _customStateController = TextEditingController();
  final _customPincodeController = TextEditingController();

  LatLng? _selectedPoint;
  late LatLng _viewportCenter;
  late double _currentZoom;
  String _selectedName = 'Selected Clinic Location';
  bool _isSearching = false;
  bool _isDraggingMarker = false;
  bool _hasMapTileError = false;
  int _tileReloadKey = 0;
  String? _searchStatus;
  String? _selectionError;
  List<Map<String, dynamic>> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    final hasValidInit = ClinicDirectionsHelper.hasValidCoordinates(
      widget.initialLat,
      widget.initialLng,
    );
    if (hasValidInit) {
      _selectedPoint = LatLng(widget.initialLat!, widget.initialLng!);
      _viewportCenter = _selectedPoint!;
      _currentZoom = OsmMapConfig.selectedPinZoom;
      _selectedName = 'Saved Clinic Location';
    } else {
      // Never pre-populate hardcoded city coordinates as a selected clinic pin.
      _selectedPoint = null;
      _viewportCenter = OsmMapConfig.defaultViewportCenter;
      _currentZoom = OsmMapConfig.defaultViewportZoom;
    }

    _hasMapTileError = OsmMapConfig.shouldSimulateNetworkError;
    _customAddressController.text = widget.initialAddress;
    _customCityController.text = widget.initialCity;
    _customStateController.text = widget.initialState;
    _customPincodeController.text = widget.initialPincode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customAddressController.dispose();
    _customCityController.dispose();
    _customStateController.dispose();
    _customPincodeController.dispose();
    super.dispose();
  }

  void _setPin(LatLng point, {double? zoom, String? label, bool moveCamera = true}) {
    final clampedLat = double.parse(point.latitude.clamp(-85.0, 85.0).toStringAsFixed(6));
    final clampedLng = double.parse(point.longitude.clamp(-180.0, 180.0).toStringAsFixed(6));
    final updatedPoint = LatLng(clampedLat, clampedLng);
    final targetZoom = (zoom ?? _currentZoom).clamp(3.0, 18.0);

    setState(() {
      _selectedPoint = updatedPoint;
      _viewportCenter = updatedPoint;
      _currentZoom = targetZoom;
      _selectionError = null;
      if (label != null && label.trim().isNotEmpty) {
        _selectedName = label.trim();
      }
    });

    if (moveCamera) {
      try {
        _mapController.move(updatedPoint, _currentZoom);
      } catch (_) {}
    }
  }

  void _handleMarkerPointerMove(Offset globalPosition) {
    final renderBox = _mapContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    try {
      final localOffset = renderBox.globalToLocal(globalPosition);
      final draggedLatLng = _mapController.camera.offsetToCrs(localOffset);
      _setPin(draggedLatLng, label: 'Adjusted Clinic Pin', moveCamera: false);
    } catch (_) {}
  }

  void _zoomBy(double delta) {
    final nextZoom = (_currentZoom + delta).clamp(3.0, 18.0);
    final targetCenter = _selectedPoint ?? _viewportCenter;
    setState(() => _currentZoom = nextZoom);
    try {
      _mapController.move(targetCenter, nextZoom);
    } catch (_) {}
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchStatus = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchStatus = null;
    });

    try {
      List<Map<String, dynamic>> results = [];
      final override = MapLocationPickerDialog.debugSearchOverride;
      if (override != null) {
        results = await override(query);
      } else {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&limit=5&q=${Uri.encodeComponent(query)}',
        );
        final res = await http.get(
          uri,
          headers: const {
            'User-Agent': 'GSHealthApp/1.0 (in.gshealth.app)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            results = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchResults = results;
        _searchStatus = results.isEmpty
            ? 'No matching places found. Tap the map or drag the pin to select your clinic location.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchResults = const [];
        _searchStatus = 'Location search unavailable right now. Tap the map to place your pin or enter your address manually.';
      });
    }
  }

  void _applySearchResult(Map<String, dynamic> item) {
    final lat = double.tryParse((item['lat'] ?? '').toString());
    final lng = double.tryParse((item['lon'] ?? item['lng'] ?? '').toString());
    if (!ClinicDirectionsHelper.hasValidCoordinates(lat, lng)) return;

    final displayName = (item['display_name'] ?? 'Selected Clinic Location').toString().trim();
    final addr = item['address'] is Map
        ? Map<String, dynamic>.from(item['address'] as Map)
        : const <String, dynamic>{};

    final foundCity = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '').toString().trim();
    final foundState = (addr['state'] ?? '').toString().trim();
    final foundPin = (addr['postcode'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');

    _setPin(
      LatLng(lat!, lng!),
      zoom: OsmMapConfig.selectedPinZoom,
      label: displayName.split(',').first,
    );
    setState(() {
      _searchResults = const [];
      _searchStatus = null;
      if (_customAddressController.text.trim().isEmpty && displayName.isNotEmpty) {
        _customAddressController.text = displayName;
      }
      if (_customCityController.text.trim().isEmpty && foundCity.isNotEmpty) {
        _customCityController.text = foundCity;
      }
      if (_customStateController.text.trim().isEmpty && foundState.isNotEmpty) {
        _customStateController.text = foundState;
      }
      if (_customPincodeController.text.trim().isEmpty && foundPin.length == 6) {
        _customPincodeController.text = foundPin;
      }
    });
  }

  void _confirmSelection() {
    final point = _selectedPoint;
    if (point == null || !ClinicDirectionsHelper.hasValidCoordinates(point.latitude, point.longitude)) {
      setState(() {
        _selectionError = 'Please tap on the map to place your clinic marker before confirming.';
      });
      return;
    }

    final result = MapLocationSelectionResult(
      address: _customAddressController.text.trim(),
      city: _customCityController.text.trim(),
      state: _customStateController.text.trim(),
      pincode: _customPincodeController.text.trim(),
      latitude: double.parse(point.latitude.toStringAsFixed(6)),
      longitude: double.parse(point.longitude.toStringAsFixed(6)),
      locationName: _selectedName,
    );

    widget.onSelectionConfirmed?.call(result);
    widget.onLocationSelected?.call(
      result.address,
      result.city,
      result.pincode,
      result.latitude,
      result.longitude,
      result.locationName,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      key: const Key('osm_location_picker_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: screenHeight * 0.90,
        ),
        padding: EdgeInsets.all(screenWidth < 380 ? 12 : 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.map_rounded, color: AppTheme.gsNavy, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isDentist ? 'Select Clinic Location' : 'Select Location on Map',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Tap map to place marker or drag marker to fine-tune',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('osm_picker_close_btn'),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Optional Place Search Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('osm_picker_search_field'),
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchPlace(),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Search area, clinic landmark, or city...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.gsNavy),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('osm_picker_search_btn'),
                  onPressed: _isSearching ? null : _searchPlace,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSearching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Find', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (_searchStatus != null) ...[
              const SizedBox(height: 6),
              Text(
                _searchStatus!,
                key: const Key('osm_picker_search_status'),
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
            ],
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 105),
                child: Material(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = _searchResults[i];
                      final name = (item['display_name'] ?? 'Place').toString();
                      return ListTile(
                        key: Key('osm_search_result_$i'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.gsRed),
                        title: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                        ),
                        onTap: () => _applySearchResult(item),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (_hasMapTileError) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('osm_map_error_banner'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Map tiles could not load. Check your connection — manual address entry remains available.',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                      ),
                    ),
                    TextButton(
                      key: const Key('osm_map_retry_btn'),
                      onPressed: () {
                        setState(() {
                          _hasMapTileError = false;
                          _tileReloadKey++;
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.gsNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: const Size(0, 26),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Retry', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),

            // Interactive OpenStreetMap Canvas
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  key: _mapContainerKey,
                  children: [
                    FlutterMap(
                      key: const Key('osm_flutter_map'),
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _viewportCenter,
                        initialZoom: _currentZoom,
                        minZoom: 3,
                        maxZoom: 18,
                        interactionOptions: InteractionOptions(
                          flags: _isDraggingMarker
                              ? InteractiveFlag.none
                              : (InteractiveFlag.drag |
                                  InteractiveFlag.pinchZoom |
                                  InteractiveFlag.scrollWheelZoom),
                        ),
                        onTap: (_, latLng) => _setPin(
                          latLng,
                          zoom: _currentZoom < 12 ? 14 : _currentZoom,
                          label: 'Selected Clinic Pin',
                        ),
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture) {
                            _viewportCenter = camera.center;
                            _currentZoom = camera.zoom;
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          key: ValueKey('osm_tile_layer_$_tileReloadKey'),
                          urlTemplate: OsmMapConfig.tileUrlTemplate,
                          userAgentPackageName: OsmMapConfig.userAgentPackageName,
                          tileProvider: OsmMapConfig.resolveTileProvider(),
                          errorTileCallback: (_, __, ___) {
                            if (mounted && !_hasMapTileError) {
                              setState(() => _hasMapTileError = true);
                            }
                          },
                        ),
                        if (_selectedPoint != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                key: const Key('osm_selected_marker'),
                                point: _selectedPoint!,
                                width: 56,
                                height: 56,
                                alignment: Alignment.topCenter,
                                child: Listener(
                                  key: const Key('osm_draggable_marker'),
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: (_) {
                                    if (!_isDraggingMarker) {
                                      setState(() => _isDraggingMarker = true);
                                    }
                                  },
                                  onPointerMove: (event) => _handleMarkerPointerMove(event.position),
                                  onPointerUp: (_) {
                                    if (_isDraggingMarker) {
                                      setState(() => _isDraggingMarker = false);
                                    }
                                  },
                                  onPointerCancel: (_) {
                                    if (_isDraggingMarker) {
                                      setState(() => _isDraggingMarker = false);
                                    }
                                  },
                                  child: const Tooltip(
                                    message: 'Drag marker to adjust clinic location',
                                    child: Icon(
                                      Icons.location_pin,
                                      color: AppTheme.gsRed,
                                      size: 46,
                                      shadows: [
                                        Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),

                    // Live Coordinates Pill
                    Positioned(
                      left: 10,
                      top: 10,
                      right: 54,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          key: const Key('osm_live_coords_pill'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            _selectedPoint != null
                                ? 'Lat: ${_selectedPoint!.latitude.toStringAsFixed(5)}, Lng: ${_selectedPoint!.longitude.toStringAsFixed(5)}'
                                : 'Tap on the map to place clinic marker',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _selectedPoint != null ? const Color(0xFF0F172A) : AppTheme.gsNavy,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Zoom Controls
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Column(
                        children: [
                          _buildMapControlButton(
                            key: const Key('osm_zoom_in_btn'),
                            icon: Icons.add_rounded,
                            onTap: () => _zoomBy(1.0),
                          ),
                          const SizedBox(height: 6),
                          _buildMapControlButton(
                            key: const Key('osm_zoom_out_btn'),
                            icon: Icons.remove_rounded,
                            onTap: () => _zoomBy(-1.0),
                          ),
                        ],
                      ),
                    ),

                    // Mandatory OpenStreetMap Attribution
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: InkWell(
                        key: const Key('osm_attribution_link'),
                        onTap: () async {
                          final uri = Uri.parse('https://www.openstreetmap.org/copyright');
                          try {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Text(
                            '© OpenStreetMap contributors',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_selectionError != null) ...[
              const SizedBox(height: 8),
              Text(
                _selectionError!,
                key: const Key('osm_picker_selection_error'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gsRed,
                ),
              ),
            ],
            const SizedBox(height: 10),

            // Manual Address Fields (Always Available)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('osm_picker_address_field'),
                    controller: _customAddressController,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      labelText: 'Clinic Address',
                      labelStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('osm_picker_city_field'),
                          controller: _customCityController,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            labelText: 'City',
                            labelStyle: TextStyle(fontSize: 11),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          key: const Key('osm_picker_state_field'),
                          controller: _customStateController,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            labelText: 'State',
                            labelStyle: TextStyle(fontSize: 11),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 92,
                        child: TextField(
                          key: const Key('osm_picker_pincode_field'),
                          controller: _customPincodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            labelText: 'Pincode',
                            labelStyle: TextStyle(fontSize: 11),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Modal Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('osm_picker_cancel_btn'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    key: const Key('osm_picker_confirm_btn'),
                    onPressed: _confirmSelection,
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text(
                      'Select Clinic Location',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gsNavy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControlButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        key: key,
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}
