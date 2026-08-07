import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProductsDropdownMenu extends StatelessWidget {
  final Color textColor;
  const ProductsDropdownMenu({super.key, this.textColor = AppTheme.textDark});

  void _showProductDetailsDialog(BuildContext context, String productName) {
    Map<String, dynamic> details = {
      'Smooth Implant': {
        'icon': Icons.medical_services_rounded,
        'tag': 'Precision Machined Surface',
        'desc': 'Engineered with a micro-smooth polished collar for minimal marginal bone loss and optimal soft-tissue seal in aesthetic zones.',
        'features': ['Grade 5 Titanium Alloy', 'Micro-grooved Neck', 'Internal Hex Connection', 'Ideal for Anterior Restoration'],
        'price': '\$180 / Unit',
        'color': const Color(0xFF0284C7),
      },
      'Rough Implant': {
        'icon': Icons.texture_rounded,
        'tag': 'SLA Acid-Etched Surface',
        'desc': 'Advanced sand-blasted & acid-etched macro/micro-roughness providing accelerated osseointegration and superior secondary stability.',
        'features': ['SLA Surface Technology', 'Self-Tapping Double Thread', 'Enhanced Bone Contact Ratio', 'High Primary Torque'],
        'price': '\$210 / Unit',
        'color': const Color(0xFFD97706),
      },
      'Combi Implant': {
        'icon': Icons.auto_awesome_rounded,
        'tag': 'Hybrid Smooth-Rough Geometry',
        'desc': 'Combines a 1.5mm smooth machined cervical collar with an SLA rough threaded body for dual soft-tissue and hard-tissue integration.',
        'features': ['Hybrid Dual-Surface', 'Conical Morse Taper Seal', 'Zero Micro-leakage Design', 'Universal Posterior & Anterior'],
        'price': '\$240 / Unit',
        'color': const Color(0xFF10B981),
      },
      'Implant Surgical Kit': {
        'icon': Icons.home_repair_service_rounded,
        'tag': 'Complete Clinical Autoclavable Kit',
        'desc': 'Fully equipped surgical tray with color-coded drill sequence, depth stoppers, torque wrench, and directional indicators.',
        'features': ['Stainless Steel Surgical Drills', 'Integrated Depth Gauge Stopper', 'Ratchet Torque Wrench (15-45 Ncm)', 'Autoclavable Modular Tray'],
        'price': '\$850 / Full Kit',
        'color': const Color(0xFF8B5CF6),
      },
    }[productName] ?? {
      'icon': Icons.inventory_2_rounded,
      'tag': 'Dental Product',
      'desc': 'High precision dental implant product.',
      'features': ['Clinical Grade', 'CE Certified'],
      'price': '\$150',
      'color': AppTheme.primaryBlue,
    };

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (details['color'] as Color).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(details['icon'] as IconData, color: details['color'] as Color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (details['color'] as Color).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            details['tag'] as String,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: details['color'] as Color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                details['desc'] as String,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text('Key Specifications:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 8),
              ...((details['features'] as List<String>).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f, style: const TextStyle(fontSize: 12, color: AppTheme.textDark)),
                      ),
                    ],
                  ),
                ),
              )),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Catalog Price', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                      Text(
                        details['price'] as String,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: details['color'] as Color),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.shopping_bag_rounded, size: 16, color: Colors.white),
                    label: const Text('Inquire Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: details['color'] as Color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🛍️ Product inquiry for "$productName" sent to sales team!'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Browse Products',
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      onSelected: (product) => _showProductDetailsDialog(context, product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PRODUCTS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: textColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: textColor),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _buildMenuItem('Smooth Implant', Icons.medical_services_outlined),
        _buildMenuItem('Rough Implant', Icons.texture_outlined),
        _buildMenuItem('Combi Implant', Icons.auto_awesome_outlined),
        _buildMenuItem('Implant Surgical Kit', Icons.home_repair_service_outlined),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(String title, IconData icon) {
    return PopupMenuItem<String>(
      value: title,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
          ),
        ],
      ),
    );
  }
}
