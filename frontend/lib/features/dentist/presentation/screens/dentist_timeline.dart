import 'package:flutter/material.dart';

class DentistTimelineScreen extends StatefulWidget {
  const DentistTimelineScreen({super.key});

  @override
  State<DentistTimelineScreen> createState() => _DentistTimelineScreenState();
}

class _DentistTimelineScreenState extends State<DentistTimelineScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dr. Rodriguez', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Dental Wing A Supervisor', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () {},
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Stats row
          Row(
            children: [
              Expanded(
                child: _buildStatBox('12', "Today's Patients", const Color(0xFF0D9488)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox('4', 'Pending Consults', const Color(0xFF0EA5E9)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. Timeline Heading
          Text('Daily Schedule Timeline', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),

          // 3. Timeline Items
          _buildTimelineSlot('08:30 AM', 'Eleanor Shellstrop', 'Routine Cleaning', 'In progress', theme),
          _buildTimelineSlot('10:15 AM', 'Chidi Anagonye', 'Orthodontic Consultation', 'Waiting in lobby', theme),
          _buildTimelineSlot('01:15 PM', 'Tahani Al-Jamil', 'Emergency Incisor Repair', 'Confirmed', theme),
        ],
      ),
    );
  }

  Widget _buildStatBox(String val, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTimelineSlot(String time, String patient, String treatment, String status, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column
          SizedBox(
            width: 75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time.split(' ')[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(time.split(' ')[1], style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          
          // Patient card
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        Text(patient, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(status, style: const TextStyle(fontSize: 9, color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(treatment, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {},
                          child: const Text('Add Clinical Notes', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          ),
                          onPressed: () {},
                          child: const Text('Diagnose', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
