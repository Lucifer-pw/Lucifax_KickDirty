import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';

/// Screen for Owner to manage Staff feature permissions.
/// All changes are saved to Firestore in real-time (auto-save per toggle).
class StaffPermissionsScreen extends StatelessWidget {
  const StaffPermissionsScreen({Key? key}) : super(key: key);

  static const String _collection = 'app_config';
  static const String _docId = 'staff_permissions';

  /// Default permission keys with metadata
  static const List<Map<String, dynamic>> _permissionItems = [
    {
      'key': 'canViewSalesCards',
      'title': 'Lihat Rekap Penjualan',
      'subtitle': 'Kartu Harian, Mingguan, Bulanan, Tahunan & chart performa',
      'icon': Icons.bar_chart_rounded,
      'color': Colors.blue,
    },
    {
      'key': 'canViewSalesDetail',
      'title': 'Lihat Detail Rekap',
      'subtitle': 'Klik kartu rekap & lihat detail transaksi + date picker',
      'icon': Icons.receipt_long,
      'color': Colors.indigo,
    },
    {
      'key': 'canManageServices',
      'title': 'Kelola Layanan',
      'subtitle': 'CRUD tarif & layanan + tab Layanan di navbar',
      'icon': Icons.cleaning_services_outlined,
      'color': Colors.deepPurple,
    },
    {
      'key': 'canViewFinancialReport',
      'title': 'Laporan Keuangan',
      'subtitle': 'Akses halaman Pemasukan & laba bersih',
      'icon': Icons.analytics_outlined,
      'color': Colors.purple,
    },
    {
      'key': 'canEditCourierFee',
      'title': 'Edit Ongkir Pesanan',
      'subtitle': 'Ubah biaya ongkir kurir per pesanan aktif',
      'icon': Icons.local_shipping_outlined,
      'color': Colors.orange,
    },
    {
      'key': 'canAccessWhatsAppSettings',
      'title': 'Pengaturan WA',
      'subtitle': 'Konfigurasi WA Gateway (Fonnte/Wablas)',
      'icon': Icons.settings_phone,
      'color': Colors.teal,
    },
    {
      'key': 'canAccessChatBotSettings',
      'title': 'Auto-Reply Chat',
      'subtitle': 'Atur salam bot otomatis untuk pelanggan',
      'icon': Icons.android,
      'color': Colors.amber,
    },
    {
      'key': 'canAccessBusinessSettings',
      'title': 'Poin & Ongkir',
      'subtitle': 'Atur tarif ongkir default & poin loyalitas',
      'icon': Icons.stars_outlined,
      'color': Colors.deepOrange,
    },
  ];

  Future<void> _togglePermission(String key, bool value) async {
    await FirebaseFirestore.instance
        .collection(_collection)
        .doc(_docId)
        .set({key: value}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hak Akses Staff'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection(_collection)
            .doc(_docId)
            .snapshots(),
        builder: (context, snapshot) {
          Map<String, dynamic> permissions = {};
          if (snapshot.hasData && snapshot.data!.exists) {
            permissions = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryBlue,
                        AppTheme.primaryBlue.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.admin_panel_settings,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kontrol Akses Real-Time',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Perubahan langsung berlaku tanpa perlu staff refresh aplikasi.',
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Always-on info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fitur yang selalu aktif untuk Staff:\nInput Pesanan, Proses Pesanan, Riwayat Transaksi, Chat Pelanggan',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Permission toggles
                const Text(
                  'Fitur yang Dapat Diatur',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkBlueText,
                  ),
                ),
                const SizedBox(height: 12),

                ..._permissionItems.map((item) {
                  final key = item['key'] as String;
                  final isEnabled = permissions[key] == true;
                  final color = item['color'] as Color;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isEnabled
                            ? color.withOpacity(0.4)
                            : AppTheme.lightGray,
                      ),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: SwitchListTile(
                      value: isEnabled,
                      onChanged: (val) => _togglePermission(key, val),
                      activeColor: color,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isEnabled
                              ? color.withOpacity(0.1)
                              : AppTheme.lightGray.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item['icon'] as IconData,
                          color: isEnabled ? color : AppTheme.textGray,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        item['title'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isEnabled
                              ? AppTheme.darkBlueText
                              : AppTheme.textGray,
                        ),
                      ),
                      subtitle: Text(
                        item['subtitle'] as String,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 24),
                const Center(child: Watermark()),
              ],
            ),
          );
        },
      ),
    );
  }
}
