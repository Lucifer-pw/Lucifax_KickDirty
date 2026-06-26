import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/update_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';
import '../login_screen.dart';
import 'input_order_screen.dart';
import 'process_order_screen.dart';
import 'history_orders_screen.dart';
import 'service_crud_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  void initState() {
    super.initState();
    // Run update check on dashboard load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    final updateService = UpdateService();
    try {
      final updateInfo = await updateService.checkForUpdate();
      if (updateInfo.hasUpdate && mounted) {
        showDialog(
          context: context,
          barrierDismissible: !updateInfo.isForceUpdate,
          builder: (context) {
            return AlertDialog(
              title: const Text('Update Aplikasi Tersedia!'),
              content: Text(
                'Versi baru (${updateInfo.latestVersion}) telah dirilis. Silakan lakukan pembaruan untuk melanjutkan penggunaan aplikasi.',
              ),
              actions: [
                if (!updateInfo.isForceUpdate)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Nanti', style: TextStyle(color: AppTheme.textGray)),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    // Open browser link to download APK
                    // ignore: deprecated_member_use
                    if (await canLaunch(updateInfo.downloadUrl)) {
                      // ignore: deprecated_member_use
                      await launch(updateInfo.downloadUrl);
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tidak dapat membuka link download')),
                        );
                      }
                    }
                  },
                  child: const Text('Unduh Update'),
                ),
              ],
            );
          },
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final dbService = Provider.of<DatabaseService>(context);
    
    final currentUser = authService.currentUserModel;
    final String roleLabel = currentUser?.role == 'owner' ? 'Owner' : 'Staff';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lucifax KickDirty'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: Colors.redAccent),
            onPressed: () async {
              await authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: dbService.getOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data ?? [];
          final recaps = dbService.calculateSalesRecap(orders);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Profile banner
                _buildProfileBanner(currentUser?.name ?? 'Admin', roleLabel),
                const SizedBox(height: 24),

                // Recap Header Title
                Text('Rekap Penjualan (Lunas)', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),

                // Recap Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double cardWidth = (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildRecapCard('Harian', recaps['daily'] ?? 0.0, Icons.today, Colors.blue, cardWidth),
                        _buildRecapCard('Mingguan', recaps['weekly'] ?? 0.0, Icons.date_range, Colors.indigo, cardWidth),
                        _buildRecapCard('Bulanan', recaps['monthly'] ?? 0.0, Icons.calendar_month, Colors.deepPurple, cardWidth),
                        _buildRecapCard('Tahunan', recaps['yearly'] ?? 0.0, Icons.analytics, Colors.teal, cardWidth),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Visual sales progress bars (custom chart simulation)
                _buildVisualChart(recaps['monthly'] ?? 0.0, recaps['yearly'] ?? 0.0),
                const SizedBox(height: 24),

                // Main navigation buttons
                Text('Menu Navigasi', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                _buildMenuGrid(),
                
                const SizedBox(height: 32),
                const Center(child: Watermark()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileBanner(String name, String role) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.2),
            radius: 28,
            child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Halo, $name',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecapCard(String title, double amount, IconData icon, Color color, double width) {
    final String formattedAmount = amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Rp $formattedAmount',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkBlueText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualChart(double monthly, double yearly) {
    // Normalization ratio for chart representation
    double ratio = yearly > 0 ? (monthly / (yearly / 12)) : 0;
    if (ratio > 1.0) ratio = 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performa Bulanan vs Target Rata-Rata',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText),
          ),
          const SizedBox(height: 16),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 14,
                width: double.infinity,
                decoration: BoxDecoration(color: AppTheme.lightGray, borderRadius: BorderRadius.circular(7)),
              ),
              FractionallySizedBox(
                widthFactor: ratio == 0 ? 0.05 : ratio,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Penjualan Bulan ini', style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}% dari rata-rata',
                style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMenuButton(
                'Input Pesanan',
                'Input cucian sepatu baru',
                Icons.add_shopping_cart,
                Colors.blue,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InputOrderScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                'Proses Pesanan',
                'Update cucian real-time',
                Icons.sync_alt,
                Colors.orange,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProcessOrderScreen())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMenuButton(
                'Riwayat Transaksi',
                'Invoice & Cetak PDF',
                Icons.history,
                Colors.green,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryOrdersScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                'Kelola Layanan',
                'CRUD tarif & layanan',
                Icons.cleaning_services_outlined,
                Colors.indigo,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServiceCrudScreen())),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuButton(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightGray),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppTheme.textGray, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
