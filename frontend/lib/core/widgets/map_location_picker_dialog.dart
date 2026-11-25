import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/patient_problem_service.dart';

class MapLocationItem {
  final String name;
  final String locality;
  final String city;
  final String pincode;
  final double latitude;
  final double longitude;

  const MapLocationItem({
    required this.name,
    required this.locality,
    required this.city,
    required this.pincode,
    required this.latitude,
    required this.longitude,
  });
}

List<MapLocationItem> _realClinicLocations() {
  return PatientProblemService().allClinics
      .where((c) => c.clinicName.trim().isNotEmpty)
      .map(
        (c) => MapLocationItem(
          name: c.clinicName.trim(),
          locality: c.location.trim(),
          city: '',
          pincode: '',
          latitude: 17.3850,
          longitude: 78.4867,
        ),
      )
      .toList();
}

class MapLocationPickerDialog extends StatefulWidget {
  final String initialAddress;
  final String initialCity;
  final String initialPincode;
  final double? initialLat;
  final double? initialLng;
  final bool isDentist;
  final Function(String address, String city, String pincode, double lat, double lng, String locationName) onLocationSelected;

  const MapLocationPickerDialog({
    super.key,
    required this.initialAddress,
    required this.initialCity,
    required this.initialPincode,
    this.initialLat,
    this.initialLng,
    this.isDentist = true,
    required this.onLocationSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required String initialAddress,
    required String initialCity,
    required String initialPincode,
    double? initialLat,
    double? initialLng,
    bool isDentist = true,
    required Function(String address, String city, String pincode, double lat, double lng, String locationName) onLocationSelected,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => MapLocationPickerDialog(
        initialAddress: initialAddress,
        initialCity: initialCity,
        initialPincode: initialPincode,
        initialLat: initialLat,
        initialLng: initialLng,
        isDentist: isDentist,
        onLocationSelected: onLocationSelected,
      ),
    );
  }

  @override
  State<MapLocationPickerDialog> createState() => _MapLocationPickerDialogState();
}

class _MapLocationPickerDialogState extends State<MapLocationPickerDialog> {
  final _searchController = TextEditingController();
  final _customAddressController = TextEditingController();
  final _customCityController = TextEditingController();
  final _customPincodeController = TextEditingController();

  late double _currentLat;
  late double _currentLng;
  String _selectedName = 'Selected Pin';
  double _zoomLevel = 1.0;
  Offset _panOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLat ?? 17.3850;
    _currentLng = widget.initialLng ?? 78.4867;
    _customAddressController.text = widget.initialAddress;
    _customCityController.text = widget.initialCity;
    _customPincodeController.text = widget.initialPincode;
  }

  void _selectLocationItem(MapLocationItem item) {
    setState(() {
      _currentLat = item.latitude;
      _currentLng = item.longitude;
      _selectedName = item.name;
      _customAddressController.text = item.locality;
      _customCityController.text = item.city;
      _customPincodeController.text = item.pincode;
      _panOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clinicLocations = _realClinicLocations();
    final query = _searchController.text.trim().toLowerCase();
    final filteredLocations = query.isEmpty
        ? clinicLocations
        : clinicLocations.where((loc) {
            return loc.name.toLowerCase().contains(query) ||
                loc.locality.toLowerCase().contains(query) ||
                loc.city.toLowerCase().contains(query) ||
                loc.pincode.contains(query);
          }).toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screenHeight * 0.88,
        ),
        padding: EdgeInsets.all(screenWidth < 400 ? 14 : 20),
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
                    color: const Color(0xFF012A58).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.map_rounded, color: Color(0xFF012A58), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isDentist ? 'Pick Clinic Location on Map' : 'Select Location on Map',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Pan map or search locality to auto-fill address, city & pincode',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 10),

            // Search Bar & GPS Action
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Search locality, area, city or pin...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF012A58)),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () => setState(() => _searchController.clear()),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF012A58), width: 1.8)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quick Locality Chips (strictly from real registered clinics)
            if (filteredLocations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No clinic locations registered yet. Enter an address or pincode manually.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: filteredLocations.take(10).map((loc) {
                  final isSelected = (_currentLat - loc.latitude).abs() < 0.005 && (_currentLng - loc.longitude).abs() < 0.005;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => _selectLocationItem(loc),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF012A58) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? const Color(0xFF012A58) : const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_rounded, size: 11, color: isSelected ? Colors.white : const Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              loc.name.split(' ').take(2).join(' '),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),

            // Interactive Simulated Map Canvas
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Gesture Detector for Map Pan
                    GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _panOffset += details.delta;
                          _currentLat -= details.delta.dy * 0.0001;
                          _currentLng += details.delta.dx * 0.0001;
                        });
                      },
                      child: CustomPaint(
                        painter: InteractiveMapGridPainter(
                          panOffset: _panOffset,
                          zoomLevel: _zoomLevel,
                          centerLat: _currentLat,
                          centerLng: _currentLng,
                        ),
                        size: Size.infinite,
                      ),
                    ),

                    // Map Center Target Pin
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_hospital_rounded, color: Color(0xFFFE3434), size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedName,
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Icon(
                            Icons.location_pin,
                            color: Color(0xFFFE3434),
                            size: 38,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Map Controls (Zoom In, Zoom Out)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () => setState(() => _zoomLevel = (_zoomLevel * 1.2).clamp(0.5, 3.0)),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.add_rounded, size: 18, color: Color(0xFF0F172A)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () => setState(() => _zoomLevel = (_zoomLevel / 1.2).clamp(0.5, 3.0)),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.remove_rounded, size: 18, color: Color(0xFF0F172A)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Live Coordinates Pill
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          'GPS: ${_currentLat.toStringAsFixed(4)}° N, ${_currentLng.toStringAsFixed(4)}° E',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Editable Address Form Section
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
                  const Text('Selected Clinic Address Details:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _customAddressController,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      labelText: 'Location / Clinic Address',
                      labelStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customCityController,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            labelText: 'City',
                            labelStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _customPincodeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            labelText: 'Pincode',
                            labelStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF012A58), Color(0xFF012A58)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final addr = _customAddressController.text.trim();
                        final city = _customCityController.text.trim();
                        final pin = _customPincodeController.text.trim();
                        widget.onLocationSelected(
                          addr.isNotEmpty ? addr : 'Selected Map Location',
                          city,
                          pin,
                          _currentLat,
                          _currentLng,
                          _selectedName,
                        );
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: const Text('Confirm Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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
}

class InteractiveMapGridPainter extends CustomPainter {
  final Offset panOffset;
  final double zoomLevel;
  final double centerLat;
  final double centerLng;

  InteractiveMapGridPainter({
    required this.panOffset,
    required this.zoomLevel,
    required this.centerLat,
    required this.centerLng,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background Map Land Color
    final bgPaint = Paint()..color = const Color(0xFFE2E8F0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Water body / Park patches
    final waterPaint = Paint()..color = const Color(0x40FE3434);
    final parkPaint = Paint()..color = const Color(0x14012A58);

    final waterRect = Rect.fromLTWH(
      (panOffset.dx * 0.5) % size.width - 60,
      (panOffset.dy * 0.5) % size.height + 40,
      140 * zoomLevel,
      80 * zoomLevel,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(waterRect, const Radius.circular(20)), waterPaint);

    final parkRect = Rect.fromLTWH(
      (panOffset.dx * 0.3) % size.width + size.width * 0.6,
      (panOffset.dy * 0.3) % size.height + size.height * 0.5,
      120 * zoomLevel,
      100 * zoomLevel,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(parkRect, const Radius.circular(16)), parkPaint);

    // 3. Grid roads & avenues
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0 * zoomLevel
      ..style = PaintingStyle.stroke;

    final roadBorderPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = (6.0 * zoomLevel) + 2
      ..style = PaintingStyle.stroke;

    final gridSpacing = 60.0 * zoomLevel;
    final startX = panOffset.dx % gridSpacing;
    final startY = panOffset.dy % gridSpacing;

    // Draw vertical road lines
    for (double x = startX - gridSpacing; x <= size.width + gridSpacing; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadBorderPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }

    // Draw horizontal road lines
    for (double y = startY - gridSpacing; y <= size.height + gridSpacing; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadBorderPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }

    // 4. Highway diagonal artery
    final highwayPaint = Paint()
      ..color = const Color(0x14FE3434)
      ..strokeWidth = 10.0 * zoomLevel
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(panOffset.dx % size.width - 50, 0),
      Offset(size.width, (panOffset.dy % size.height) + size.height + 50),
      highwayPaint,
    );
  }

  @override
  bool shouldRepaint(covariant InteractiveMapGridPainter oldDelegate) {
    return oldDelegate.panOffset != panOffset ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.centerLat != centerLat ||
        oldDelegate.centerLng != centerLng;
  }
}
