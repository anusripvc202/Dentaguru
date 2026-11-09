import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import 'package:go_router/go_router.dart';

class ClinicDashboardScreen extends StatefulWidget {
  const ClinicDashboardScreen({super.key});

  @override
  State<ClinicDashboardScreen> createState() => _ClinicDashboardScreenState();
}

class _ClinicDashboardScreenState extends State<ClinicDashboardScreen> {
  int _currentIndex = 0;
  final PatientProblemService _problemService = PatientProblemService();

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceUpdate);
    _loadSavedProcedurePrices();
    _problemService.syncAllDataFromApi();
  }

  Future<void> _loadSavedProcedurePrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dentaguru_clinic_procedure_prices');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && mounted) {
          setState(() {
            decoded.forEach((k, v) {
              _procedurePrices[k.toString()] = v.toString();
            });
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveProcedurePrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dentaguru_clinic_procedure_prices', jsonEncode(_procedurePrices));
    } catch (_) {}
  }

  @override
  void dispose() {
    _problemService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: DentaGuruLogo(height: 28),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Log Out',
            onPressed: () async {
              await SessionService().clearSession();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logged out of Clinic workspace.'),
                  duration: Duration(seconds: 2),
                ),
              );
              context.go('/login');
            },
          ),
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
    final doctors = _problemService.allDoctors;
    final requests = _problemService.requests;

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
                child: _buildMetricCard('${doctors.length}', 'Attached Doctors', Colors.teal, theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard('${requests.length}', 'Total Bookings', Colors.blue, theme),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Monday - Friday'),
                      Text('09:00 AM - 08:00 PM', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
    final doctors = _problemService.allDoctors;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Attached Doctors (${doctors.length})', style: theme.textTheme.titleMedium),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Colors.white),
              label: const Text('Add Doctor', style: TextStyle(color: Colors.white, fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () => _showAddDoctorDialog(context),
            )
          ],
        ),
        const SizedBox(height: 16),
        if (doctors.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('No attached doctors in directory.', style: TextStyle(color: Colors.grey))),
          )
        else
          ...doctors.map((doc) => _buildDoctorListRow(doc)),
      ],
    );
  }

  Widget _buildDoctorListRow(DoctorModel doc) {
    final isAvailable = doc.status == 'Available';
    final statusColor = isAvailable ? Colors.green : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: Color(0xFF0D9488)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(doc.specialty, style: const TextStyle(fontSize: 12, color: Color(0xFF0D9488), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(doc.status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Mobile: ${doc.phone.isNotEmpty ? doc.phone : "Not provided"} • City: ${doc.city.isNotEmpty ? doc.city : "Not provided"} • PIN: ${doc.pincode.isNotEmpty ? doc.pincode : "Not provided"} • Languages: ${doc.languages.isNotEmpty ? doc.languages.join(", ") : "English"} • Email: ${doc.email.isNotEmpty ? doc.email : "Not provided"}',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  final Map<String, String> _procedurePrices = {
    'General Consultation & Checkup': '\$75',
    'Tooth Decay / Cavity Filling': '\$85',
    'Periodontics & Gum Care': '\$95',
    'Tooth Extraction Surgery': '\$110',
    'Root Canal Therapy (RCT)': '\$180',
    'Orthodontic Consultation & Braces': '\$200',
  };

  void _showEditPriceDialog(String service, String currentPrice) {
    final priceCtrl = TextEditingController(text: currentPrice);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Edit Rate for $service', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: priceCtrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
            cursorColor: const Color(0xFF0D9488),
            decoration: InputDecoration(
              labelText: 'New Procedure Rate',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                setState(() {
                  _procedurePrices[service] = priceCtrl.text.trim();
                });
                _saveProcedurePrices();
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('💰 Rate for $service updated to ${priceCtrl.text.trim()}!')),
                );
              },
              child: const Text('Save Rate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddProcedureDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '\$75');
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Add Procedure Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                cursorColor: const Color(0xFF0D9488),
                decoration: InputDecoration(
                  labelText: 'Procedure Name *',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                cursorColor: const Color(0xFF0D9488),
                decoration: InputDecoration(
                  labelText: 'Rate *',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final rate = priceCtrl.text.trim();
                if (name.isEmpty || rate.isEmpty) return;
                setState(() {
                  _procedurePrices[name] = rate;
                });
                _saveProcedurePrices();
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Added procedure "$name" ($rate)')),
                );
              },
              child: const Text('Add Procedure', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddDoctorDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    final specialtyCtrl = TextEditingController(text: 'General Dentistry');
    final expCtrl = TextEditingController(text: '5');
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    final clinicName = SessionService().currentSession?.name ?? 'GS HEALTH Partner Clinic';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Add Attached Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    label: const Text.rich(
                      TextSpan(
                        text: 'Doctor Full Name',
                        style: TextStyle(color: Color(0xFF0F172A)),
                        children: [
                          TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    label: const Text.rich(
                      TextSpan(
                        text: 'Contact Number',
                        style: TextStyle(color: Color(0xFF0F172A)),
                        children: [
                          TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: licenseCtrl,
                  decoration: InputDecoration(
                    labelText: 'Dental License Number (Optional)',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: specialtyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Specialty (Optional)',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: expCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Experience (Years)',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cityCtrl,
                        decoration: InputDecoration(
                          labelText: 'City (Optional)',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: pincodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Pincode (Optional)',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address (Optional)',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final license = licenseCtrl.text.trim();
                final specialty = specialtyCtrl.text.trim();
                final city = cityCtrl.text.trim();
                final pincode = pincodeCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('⚠️ Full Name is mandatory.')),
                  );
                  return;
                }
                final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                if (cleanPhone.length < 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('⚠️ Enter a valid 10-digit Contact Number.')),
                  );
                  return;
                }
                final expYears = int.tryParse(expCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                _problemService.registerDoctor(
                  name: name,
                  phone: phone,
                  email: emailCtrl.text.trim(),
                  licenseNumber: license.isNotEmpty ? license : 'DEN-LIC-REG',
                  specialty: specialty.isNotEmpty ? specialty : 'General Dentistry',
                  clinicName: clinicName,
                  experienceYears: expYears,
                  city: city,
                  pincode: pincode,
                );
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('🎉 Doctor $name added to clinic directory!')),
                );
              },
              child: const Text('Save Doctor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServicesTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Procedure Price List', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add_box_outlined, color: Color(0xFF0D9488)),
              onPressed: () => _showAddProcedureDialog(context),
            )
          ],
        ),
        const SizedBox(height: 16),
        ..._procedurePrices.entries.map((entry) => _buildServicePricingRow(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildServicePricingRow(String service, String price) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(service, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(price, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 16)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF0D9488)),
              onPressed: () => _showEditPriceDialog(service, price),
            ),
          ],
        ),
        subtitle: const Text('Duration: 45 Mins • Standard Practice Rate'),
      ),
    );
  }
}
