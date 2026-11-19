import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/referral_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';

class AdminReferralsScreen extends StatefulWidget {
  const AdminReferralsScreen({super.key});

  @override
  State<AdminReferralsScreen> createState() => _AdminReferralsScreenState();
}

class _AdminReferralsScreenState extends State<AdminReferralsScreen> {
  final PatientProblemService _problemService = PatientProblemService();
  String _selectedStatus = 'All';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceChanged);
    _problemService.syncAdminReferralsFromApi();
  }

  @override
  void dispose() {
    _problemService.removeListener(_onServiceChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<PatientReferral> _getFilteredReferrals() {
    final list = _problemService.adminPatientReferrals;
    return list.where((r) {
      if (_selectedStatus != 'All' && r.status.toLowerCase() != _selectedStatus.toLowerCase()) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matchPatient = r.referredPatientName.toLowerCase().contains(q) ||
            r.referredPatientMobile.contains(q) ||
            r.referredPatientCity.toLowerCase().contains(q);
        final matchDoctor = r.doctorName.toLowerCase().contains(q) ||
            r.doctorSpecialty.toLowerCase().contains(q) ||
            r.doctorClinicName.toLowerCase().contains(q);
        final matchReferrer = r.referrerPatientName.toLowerCase().contains(q) ||
            r.referrerPatientPhone.contains(q);
        final matchComplaint = r.clinicalComplaint.toLowerCase().contains(q);
        if (!matchPatient && !matchDoctor && !matchReferrer && !matchComplaint) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
      case 'completed':
        return const Color(0xFFFE3434);
      case 'pending':
        return const Color(0xFFFE3434);
      case 'rejected':
      case 'cancelled':
        return const Color(0xFFFE3434);
      default:
        return const Color(0xFF475569);
    }
  }

  Color _getStatusBg(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
      case 'completed':
        return const Color(0x14012A58);
      case 'pending':
        return const Color(0x14FE3434);
      case 'rejected':
      case 'cancelled':
        return const Color(0x14FE3434);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}, ${dt.year}';
  }

  void _showReferralDetailsSheet(BuildContext context, PatientReferral ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final statusColor = _getStatusColor(ref.status);
        final statusBg = _getStatusBg(ref.status);

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: const Text(
                        'Referral Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        ref.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Patient Info
                _detailTile('Referred Patient', ref.referredPatientName),
                if (ref.referredPatientMobile.isNotEmpty)
                  _detailTile('Patient Mobile', ref.referredPatientMobile),
                if (ref.referredPatientCity.isNotEmpty)
                  _detailTile('City / Location', ref.referredPatientCity),
                if (ref.doctorName.isNotEmpty)
                  _detailTile('Assigned Doctor', '${ref.doctorName} (${ref.doctorSpecialty})'),
                if (ref.doctorClinicName.isNotEmpty)
                  _detailTile('Clinic Facility', ref.doctorClinicName),
                if (ref.clinicalComplaint.isNotEmpty)
                  _detailTile('Chief Complaint', ref.clinicalComplaint),
                if (ref.referrerPatientName.isNotEmpty)
                  _detailTile('Referred By', '${ref.referrerPatientName} (${ref.referrerPatientPhone})'),
                _detailTile('Date', _formatDate(ref.createdAt)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gsNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRefs = _problemService.adminPatientReferrals;
    final filtered = _getFilteredReferrals();
    final pendingCount = allRefs.where((r) => r.status.toLowerCase() == 'pending').length;
    final acceptedCount = allRefs.where((r) => r.status.toLowerCase() == 'accepted' || r.status.toLowerCase() == 'completed').length;
    final rejectedCount = allRefs.where((r) => r.status.toLowerCase() == 'rejected' || r.status.toLowerCase() == 'cancelled').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  InkWell(
                    key: const Key('admin_referrals_back_button'),
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        context.go('/admin');
                      }
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Icon(Icons.chevron_left_rounded, color: Color(0xFF0F172A), size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Referrals',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.gsNavy),
                    onPressed: () => _problemService.syncAdminReferralsFromApi(),
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _problemService.syncAdminReferralsFromApi(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    // Analytics Summary Cards
                    Row(
                      children: [
                        Expanded(child: _metricCard('Total', '${allRefs.length}', const Color(0xFF012A58))),
                        const SizedBox(width: 8),
                        Expanded(child: _metricCard('Pending', '$pendingCount', const Color(0xFFFE3434))),
                        const SizedBox(width: 8),
                        Expanded(child: _metricCard('Accepted', '$acceptedCount', const Color(0xFFFE3434))),
                        const SizedBox(width: 8),
                        Expanded(child: _metricCard('Rejected', '$rejectedCount', const Color(0xFFFE3434))),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Search input
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        key: const Key('admin_referrals_search_input'),
                        controller: _searchCtrl,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search by patient, doctor, or city...',
                          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Pending', 'Accepted', 'Rejected'].map((status) {
                          final isSelected = _selectedStatus == status;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(status),
                              selected: isSelected,
                              selectedColor: AppTheme.gsNavy,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              onSelected: (_) => setState(() => _selectedStatus = status),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Referral Cards or Clean Empty State
                    if (filtered.isEmpty)
                      Container(
                        key: const Key('admin_referrals_empty_view'),
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.folder_open_rounded, size: 32, color: Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No referral records found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _searchQuery.isNotEmpty || _selectedStatus != 'All'
                                  ? 'Try adjusting your search query or status filter.'
                                  : 'Referrals will appear here when specialist cases are assigned.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      )
                    else
                      ...filtered.map((ref) => _buildReferralCard(ref)),

                    const SizedBox(height: 24),
                    const Center(
                      child: GsHealthLogo(height: 26, alignment: Alignment.center),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard(PatientReferral ref) {
    final statusColor = _getStatusColor(ref.status);
    final statusBg = _getStatusBg(ref.status);

    return Container(
      key: Key('admin_referral_card_${ref.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: () => _showReferralDetailsSheet(context, ref),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ref.referredPatientName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (ref.referredPatientMobile.isNotEmpty || ref.referredPatientCity.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (ref.referredPatientMobile.isNotEmpty) ref.referredPatientMobile,
                              if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ref.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (ref.doctorName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 15, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Assigned: ${ref.doctorName} (${ref.doctorSpecialty})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (ref.clinicalComplaint.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes_rounded, size: 15, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ref.clinicalComplaint,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(ref.createdAt),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                  ),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View details',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.gsNavy),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
