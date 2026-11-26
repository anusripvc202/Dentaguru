import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Multi-select dialog allowing Clinic Administrators (or Main Admin) to search
/// existing registered GS Health doctors by Name, Mobile Number, or Doctor ID,
/// filter by Specialization, and associate one or multiple doctors with a clinic
/// without ever creating duplicate doctor accounts or duplicate associations.
class ClinicAddDoctorsDialog extends StatefulWidget {
  final String clinicId;
  final String clinicName;
  final List<DoctorModel> allRegisteredDoctors;
  final Set<String> alreadyAssociatedDoctorIds;
  final VoidCallback? onDoctorsAssociated;

  const ClinicAddDoctorsDialog({
    super.key,
    required this.clinicId,
    required this.clinicName,
    required this.allRegisteredDoctors,
    required this.alreadyAssociatedDoctorIds,
    this.onDoctorsAssociated,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String clinicId,
    required String clinicName,
    required List<DoctorModel> allRegisteredDoctors,
    required Set<String> alreadyAssociatedDoctorIds,
    VoidCallback? onDoctorsAssociated,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ClinicAddDoctorsDialog(
        clinicId: clinicId,
        clinicName: clinicName,
        allRegisteredDoctors: allRegisteredDoctors,
        alreadyAssociatedDoctorIds: alreadyAssociatedDoctorIds,
        onDoctorsAssociated: onDoctorsAssociated,
      ),
    );
  }

  @override
  State<ClinicAddDoctorsDialog> createState() => _ClinicAddDoctorsDialogState();
}

class _ClinicAddDoctorsDialogState extends State<ClinicAddDoctorsDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedSpecialty = 'All';
  final Set<String> _selectedDoctorIds = <String>{};
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _availableSpecialties {
    final set = <String>{'All'};
    for (final d in widget.allRegisteredDoctors) {
      final sp = d.specialty.trim();
      if (sp.isNotEmpty) set.add(sp);
    }
    return set.toList();
  }

  bool _isAlreadyAssociated(DoctorModel d) {
    return widget.alreadyAssociatedDoctorIds.contains(d.id.trim()) ||
        (d.userId.trim().isNotEmpty &&
            widget.alreadyAssociatedDoctorIds.contains(d.userId.trim())) ||
        (widget.clinicId.trim().isNotEmpty && d.clinicId.trim() == widget.clinicId.trim());
  }

  List<DoctorModel> get _filteredDoctors {
    final kw = _searchController.text.trim().toLowerCase();
    final kwDigits = kw.replaceAll(RegExp(r'\D'), '');
    return widget.allRegisteredDoctors.where((d) {
      if (_selectedSpecialty != 'All' &&
          d.specialty.trim().toLowerCase() != _selectedSpecialty.toLowerCase()) {
        return false;
      }
      if (kw.isEmpty) return true;
      final nameMatch = d.name.toLowerCase().contains(kw);
      final idMatch = d.id.toLowerCase().contains(kw) || d.userId.toLowerCase().contains(kw);
      final phoneMatch = d.phone.toLowerCase().contains(kw) ||
          (kwDigits.length >= 3 && d.phone.replaceAll(RegExp(r'\D'), '').contains(kwDigits));
      final specMatch = d.specialty.toLowerCase().contains(kw);
      return nameMatch || idMatch || phoneMatch || specMatch;
    }).toList();
  }

  Future<void> _submitAssociation() async {
    if (_selectedDoctorIds.isEmpty || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final res = await ApiService().associateDoctorsToClinic(
      clinicId: widget.clinicId,
      doctorIds: _selectedDoctorIds.toList(),
      clinicName: widget.clinicName,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      widget.onDoctorsAssociated?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res['message'] ?? '${_selectedDoctorIds.length} doctor(s) added to ${widget.clinicName}.')
                .toString(),
          ),
          backgroundColor: AppTheme.gsNavy,
        ),
      );
    } else {
      setState(() {
        _errorMessage = (res['message'] ?? 'Unable to associate selected doctors.').toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDoctors;
    final specialties = _availableSpecialties;
    final effectiveSpecialty = specialties.contains(_selectedSpecialty) ? _selectedSpecialty : 'All';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.gsNavy, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Doctors to Clinic',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Associate existing registered doctors with ${widget.clinicName}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search & Specialization Filter
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 340,
                  child: TextField(
                    key: const Key('clinic_add_doctors_search_field'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by Name, Mobile Number, or Doctor ID...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: const Key('clinic_add_doctors_specialty_filter'),
                    initialValue: effectiveSpecialty,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Specialization',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: specialties
                        .map((sp) => DropdownMenuItem(value: sp, child: Text(sp, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedSpecialty = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Text(
                  '${filtered.length} registered doctor(s) found',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                ),
                const Spacer(),
                if (_selectedDoctorIds.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedDoctorIds.length} selected',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                    ),
                  ),
              ],
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gsRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.gsRed),
                ),
              ),
            ],

            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_outlined, size: 40, color: AppTheme.textMuted.withValues(alpha: 0.6)),
                          const SizedBox(height: 8),
                          const Text(
                            'No matching registered doctors found',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Only existing registered doctors can be associated with a clinic.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final doc = filtered[idx];
                        final alreadyAssoc = _isAlreadyAssociated(doc);
                        final isSelected = _selectedDoctorIds.contains(doc.id);
                        final hasBytes = doc.photoBytes != null && doc.photoBytes!.isNotEmpty;
                        final hasUrl = (doc.profileImageUrl ?? '').trim().isNotEmpty;

                        return InkWell(
                          key: Key('clinic_add_doctor_item_${doc.id}'),
                          onTap: alreadyAssoc
                              ? null
                              : () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedDoctorIds.remove(doc.id);
                                    } else {
                                      _selectedDoctorIds.add(doc.id);
                                    }
                                  });
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: alreadyAssoc
                                  ? const Color(0xFFF8FAFC)
                                  : (isSelected ? AppTheme.gsNavy.withValues(alpha: 0.06) : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: alreadyAssoc ? true : isSelected,
                                  onChanged: alreadyAssoc
                                      ? null
                                      : (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedDoctorIds.add(doc.id);
                                            } else {
                                              _selectedDoctorIds.remove(doc.id);
                                            }
                                          });
                                        },
                                ),
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.1),
                                  backgroundImage: hasBytes
                                      ? MemoryImage(doc.photoBytes!)
                                      : (hasUrl ? NetworkImage(doc.profileImageUrl!) as ImageProvider : null),
                                  child: (!hasBytes && !hasUrl)
                                      ? const Icon(Icons.person_rounded, color: AppTheme.gsNavy, size: 20)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.name,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${doc.specialty} • ID: ${doc.id}',
                                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (doc.phone.trim().isNotEmpty)
                                        Text(
                                          'Mobile: ${doc.phone}',
                                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: alreadyAssoc
                                        ? const Color(0xFF059669).withValues(alpha: 0.12)
                                        : const Color(0xFF64748B).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    alreadyAssoc ? 'Associated' : 'Available',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: alreadyAssoc ? const Color(0xFF059669) : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  key: const Key('clinic_add_doctors_confirm_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (_selectedDoctorIds.isEmpty || _isSubmitting) ? null : _submitAssociation,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _selectedDoctorIds.isEmpty
                        ? 'Add Selected Doctors'
                        : 'Add ${_selectedDoctorIds.length} Doctor${_selectedDoctorIds.length > 1 ? 's' : ''}',
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
