import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Super Admin Portal', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Denta Guru Ecosystem Manager', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildMetricsTab(theme),
          _buildApprovalsTab(theme),
          _buildCmsTab(theme),
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
          BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'Analytics'),
          BottomNavigationBarItem(icon: Icon(Icons.verified_user_outlined), label: 'Approvals'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), label: 'CMS Broadcast'),
        ],
      ),
    );
  }

  Widget _buildMetricsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Platform Overview', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          
          // 2x2 grid of metrics cards
          _buildMetricsGridRow('Total Clinics', '15', '+2 new this week', Colors.teal),
          const SizedBox(height: 12),
          _buildMetricsGridRow('Active Dentists', '48', '+5 verified', Colors.blue),
          const SizedBox(height: 12),
          _buildMetricsGridRow('Registered Patients', '2,308', '+142 new cases', Colors.purple),
          const SizedBox(height: 12),
          _buildMetricsGridRow('Platform Revenue', '₹24,85,200', '+15.2% Commission margins', Colors.green),
        ],
      ),
    );
  }

  Widget _buildMetricsGridRow(String title, String val, String caption, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.between,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(caption, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Pending Verifications Queue', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildVerificationCard('Smile Craft Dental Care', 'Clinic Registration Application', 'Sector 15, Gurgaon', theme),
        const SizedBox(height: 12),
        _buildVerificationCard('Dr. Amanda Ross', 'Dentist License Verification', 'Associated Clinic: DentaCare Specialists', theme),
        const SizedBox(height: 12),
        _buildVerificationCard('Metro Dentists Hub', 'Clinic Registration Application', 'Saket, New Delhi', theme),
      ],
    );
  }

  Widget _buildVerificationCard(String name, String type, String details, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(type, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(details, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Reject', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  onPressed: () {},
                  child: const Text('Approve', style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCmsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compose Push Notification Broadcast', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Notification Header',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          
          TextField(
            controller: _bodyController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message Body',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill out all fields.')),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notification Broadcast Dispatched successfully.')),
              );
              _titleController.clear();
              _bodyController.clear();
            },
            child: const Text('Send Broadcast Alert', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
