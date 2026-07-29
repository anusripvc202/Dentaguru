import 'package:flutter/material.dart';

class ClinicDashboardScreen extends StatefulWidget {
  const ClinicDashboardScreen({super.key});

  @override
  State<ClinicDashboardScreen> createState() => _ClinicDashboardScreenState();
}

class _ClinicDashboardScreenState extends State<ClinicDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Smile Craft Dental Care', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Partner Clinic Panel', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          )
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildOverviewTab(theme),
          _buildDoctorsTab(theme),
          _buildServicesTab(theme),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF0D9488),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: 'Doctors'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Services'),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clinic Insights', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          
          // Row of stats cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard('₹2,48,500', 'Gross Monthly', Colors.teal, theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard('48', 'Total Bookings', Colors.blue, theme),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Working hours card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.watch_later_outlined, color: Color(0xFF0D9488)),
                      const SizedBox(width: 8),
                      Text('Working Hours', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      Text('Monday - Friday'),
                      Text('09:00 AM - 08:00 PM', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      Text('Saturday'),
                      Text('10:00 AM - 05:00 PM', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Platform active subscription details
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.between,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Premium subscription', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Renew date: Aug 24, 2026', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('ACTIVE', style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMetricCard(String val, String label, Color color, ThemeData theme) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.between,
          children: [
            Text('Attached Doctors', style: theme.textTheme.titleMedium),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Colors.white),
              label: const Text('Add Doctor', style: TextStyle(color: Colors.white, fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {},
            )
          ],
        ),
        const SizedBox(height: 16),
        _buildDoctorListRow('Dr. Michael Chen', 'General Dentist', 'Available', Colors.green),
        _buildDoctorListRow('Dr. Clara Rodriguez', 'Orthodontist', 'Available', Colors.green),
        _buildDoctorListRow('Dr. Julia Roberts', 'Pediatric Specialist', 'Offline', Colors.grey),
      ],
    );
  }

  Widget _buildDoctorListRow(String name, String spec, String status, Color statusColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF0D9488).withOpacity(0.1),
          child: const Icon(Icons.person, color: Color(0xFF0D9488)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(spec),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildServicesTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.between,
          children: [
            Text('Services Configure', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add_box_outlined, color: Color(0xFF0D9488)),
              onPressed: () {},
            )
          ],
        ),
        const SizedBox(height: 16),
        _buildServicePricingRow('Routine Cleaning & Oral Checkup', '₹1,500'),
        _buildServicePricingRow('Deep Cleaning & Scaling', '₹2,800'),
        _buildServicePricingRow('Tooth Whitening', '₹12,000'),
        _buildServicePricingRow('Root Canal Therapy', '₹8,500'),
      ],
    );
  }

  Widget _buildServicePricingRow(String service, String price) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(service, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: Text(price, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 16)),
        subtitle: const Text('Duration: 45 Mins'),
      ),
    );
  }
}
