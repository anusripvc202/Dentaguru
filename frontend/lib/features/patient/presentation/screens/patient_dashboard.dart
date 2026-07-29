import 'package:flutter/material.dart';

class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF0D9488),
              child: Text('SJ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello, Sarah', style: theme.textTheme.titleMedium),
                const Text('Ready for your dental checkup?', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            )
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          )
        ],
      ),
      body: _currentIndex == 0 ? _buildHomeView(theme) : _buildRecordsView(theme),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF0D9488),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Records'),
        ],
      ),
    );
  }

  Widget _buildHomeView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Search Bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Search Clinics, Dentists, Treatments...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 2. Next Appointment Card
          Card(
            color: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'NEXT APPOINTMENT',
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Oct 24, 2026 at 09:30 AM',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.medical_services_outlined, color: Colors.grey, size: 16),
                      SizedBox(width: 8),
                      Text('Dr. Clara Rodriguez (Smile Craft)', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                          onPressed: () {},
                          child: const Text('Reschedule', style: TextStyle(color: Colors.white)),
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. Featured Categories
          Text('Dental Categories', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryChip('All Clinics', true),
                _buildCategoryChip('Orthodontist', false),
                _buildCategoryChip('Root Canal', false),
                _buildCategoryChip('Whitening', false),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 4. Clinics List
          Text('Featured Partners', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildClinicCard(
            'Smile Craft Dental Care',
            'Sector 15, Gurgaon',
            '⭐ 4.9 (42 reviews)',
            theme,
          ),
          const SizedBox(height: 12),
          _buildClinicCard(
            'Apex Orthodontics & Implants',
            'Saket, New Delhi',
            '⭐ 4.8 (89 reviews)',
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsView(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Digital Medical Records', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildRecordCard(
          'Deep Cleaning & Periodontal Check',
          'Oct 24, 2026 • Dr. Sarah Jenkins',
          'Prescription: Chlorhexidine mouthwash (0.12%)',
          true,
        ),
        const SizedBox(height: 12),
        _buildRecordCard(
          'Wisdom Tooth Extraction',
          'Aug 12, 2025 • Dr. Marcus Chan',
          'X-Rays: Full Panoramic Scan Approved',
          false,
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label),
        backgroundColor: isSelected ? const Color(0xFF0D9488) : Colors.transparent,
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildClinicCard(String name, String location, String rating, ThemeData theme) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF0D9488).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.local_hospital, color: Color(0xFF0D9488)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(location),
            const SizedBox(height: 4),
            Text(rating, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.amber)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildRecordCard(String title, String subtitle, String details, bool hasPrescription) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(details, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
