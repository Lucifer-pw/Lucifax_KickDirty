import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../models/order_model.dart';
import '../../models/expense_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';
import '../../widgets/update_dialog.dart';
import '../login_screen.dart';
import 'input_order_screen.dart';
import 'process_order_screen.dart';
import 'history_orders_screen.dart';
import 'service_crud_screen.dart';
import 'financial_report_screen.dart';
import 'admin_chat_list_screen.dart';
import 'sales_detail_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _showNetProfit = false;

  @override
  void initState() {
    super.initState();
    // Run update check on dashboard load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    await UpdateDialog.checkAndShow(context);
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryBlue : AppTheme.textGray,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final dbService = Provider.of<DatabaseService>(context);
    
    final currentUser = authService.currentUserModel;
    final String roleLabel = currentUser?.role == 'owner' ? 'Owner' : 'Staff';

    final List<Widget> screens = [
      _buildDashboardHome(context, dbService, currentUser, roleLabel),
      InputOrderScreen(isTab: true, onOrderSubmitted: () => _onTabTapped(0)),
      const ProcessOrderScreen(isTab: true),
      const HistoryOrdersScreen(isTab: true),
      const AdminChatListScreen(isTab: true),
      const ServiceCrudScreen(isTab: true),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentIndex != 0) {
          _onTabTapped(0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.grid_view, 'Beranda'),
                _buildNavItem(1, Icons.add_shopping_cart, 'Input'),
                _buildNavItem(2, Icons.sync_alt, 'Proses'),
                _buildNavItem(3, Icons.history, 'Riwayat'),
                _buildNavItem(4, Icons.chat_outlined, 'Pesan'),
                _buildNavItem(5, Icons.cleaning_services_outlined, 'Layanan'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHome(BuildContext context, DatabaseService dbService, UserModel? currentUser, String roleLabel) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KickDirty Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: Colors.redAccent),
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: dbService.getOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data ?? [];
          final recaps = dbService.calculateSalesRecap(orders);

          return StreamBuilder<List<ExpenseModel>>(
            stream: dbService.getExpenses(),
            builder: (context, expSnapshot) {
              final expenses = expSnapshot.data ?? [];
              final expRecaps = dbService.calculateExpensesRecap(expenses);

              final displayRecaps = _showNetProfit
                  ? {
                      'daily': (recaps['daily'] ?? 0.0) - (expRecaps['daily'] ?? 0.0),
                      'weekly': (recaps['weekly'] ?? 0.0) - (expRecaps['weekly'] ?? 0.0),
                      'monthly': (recaps['monthly'] ?? 0.0) - (expRecaps['monthly'] ?? 0.0),
                      'yearly': (recaps['yearly'] ?? 0.0) - (expRecaps['yearly'] ?? 0.0),
                    }
                  : recaps;

              final newOrdersCount = orders.where((o) => o.status == 'diterima').length;
              final activeOrdersCount = orders.where((o) => o.status != 'diambil').length;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileBanner(currentUser?.name ?? 'Admin', roleLabel),
                    const SizedBox(height: 16),
                    
                    // Notification banner for new & running orders
                    if (newOrdersCount > 0 || activeOrdersCount > 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.notifications_active, color: AppTheme.primaryBlue, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (newOrdersCount > 0)
                                    Text(
                                      'Ada $newOrdersCount pesanan baru masuk!',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold, 
                                        color: AppTheme.primaryBlue,
                                        fontSize: 13
                                      ),
                                    ),
                                  Text(
                                    'Total $activeOrdersCount transaksi berjalan belum selesai.',
                                    style: TextStyle(
                                      color: AppTheme.darkBlueText,
                                      fontSize: 12,
                                      fontWeight: newOrdersCount > 0 ? FontWeight.normal : FontWeight.bold
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _showNetProfit ? 'Rekap Keuntungan Bersih' : 'Rekap Penjualan (Lunas)',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                        ),
                        Row(
                          children: [
                            const Text('Laba Bersih', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
                            const SizedBox(width: 4),
                            Switch(
                              value: _showNetProfit,
                              activeColor: AppTheme.primaryBlue,
                              onChanged: (val) {
                                setState(() {
                                  _showNetProfit = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final double cardWidth = (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildRecapCard('Harian', 'daily', displayRecaps['daily'] ?? 0.0, Icons.today, Colors.blue, cardWidth, orders),
                            _buildRecapCard('Mingguan', 'weekly', displayRecaps['weekly'] ?? 0.0, Icons.date_range, Colors.indigo, cardWidth, orders),
                            _buildRecapCard('Bulanan', 'monthly', displayRecaps['monthly'] ?? 0.0, Icons.calendar_month, Colors.deepPurple, cardWidth, orders),
                            _buildRecapCard('Tahunan', 'yearly', displayRecaps['yearly'] ?? 0.0, Icons.analytics, Colors.teal, cardWidth, orders),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildVisualChart(displayRecaps['monthly'] ?? 0.0, displayRecaps['yearly'] ?? 0.0),
                    const SizedBox(height: 24),
                    Text('Menu Navigasi', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildMenuGrid(),
                    const SizedBox(height: 32),
                    const Center(child: Watermark()),
                  ],
                ),
              );
            },
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

  Widget _buildRecapCard(String title, String periodKey, double amount, IconData icon, Color color, double width, List<OrderModel> orders) {
    final bool isNegative = amount < 0;
    final double absoluteAmount = amount.abs();
    final String formattedAmount = absoluteAmount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SalesDetailScreen(
              periodTitle: title,
              periodKey: periodKey,
              totalAmount: absoluteAmount,
              allOrders: orders,
              themeColor: color,
            ),
          ),
        );
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isNegative ? Colors.red.shade100 : AppTheme.lightGray),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isNegative ? Colors.red.withOpacity(0.1) : color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: isNegative ? Colors.red : color, size: 20),
                ),
                if (isNegative)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'RUGI',
                      style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, size: 18, color: color.withOpacity(0.5)),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              '${isNegative ? "-" : ""}Rp $formattedAmount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isNegative ? Colors.red.shade700 : AppTheme.darkBlueText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualChart(double monthly, double yearly) {
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
                () => _onTabTapped(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                'Proses Pesanan',
                'Update cucian real-time',
                Icons.sync_alt,
                Colors.orange,
                () => _onTabTapped(2),
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
                () => _onTabTapped(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                'Kelola Layanan',
                'CRUD tarif & layanan',
                Icons.cleaning_services_outlined,
                Colors.indigo,
                () => _onTabTapped(5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMenuButton(
                'Pesan Masuk',
                'Chat dengan pelanggan',
                Icons.chat_outlined,
                Colors.pink,
                () => _onTabTapped(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                'Laporan Keuangan',
                'Pemasukan & laba bersih',
                Icons.analytics_outlined,
                Colors.purple,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FinancialReportScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMenuButton(
                'Pengaturan WA',
                'Konfigurasi WA Gateway',
                Icons.settings_phone,
                Colors.teal,
                _showWhatsAppSettingsDialog,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                'Auto-Reply Chat',
                'Salam bot otomatis',
                Icons.android,
                Colors.amber,
                _showChatBotSettingsDialog,
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

  void _showWhatsAppSettingsDialog() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> data = {};
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('whatsapp_config').get();
      if (doc.exists) {
        data = doc.data() ?? {};
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context); // Close loading

    String provider = data['provider'] ?? 'manual';
    bool useAutomation = data['useAutomation'] ?? false;
    final tokenController = TextEditingController(text: data['apiToken'] ?? '');
    final urlController = TextEditingController(text: data['gatewayUrl'] ?? 'https://api.wablas.com');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Pengaturan WA Gateway'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Aktifkan Otomasi WA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Kirim notifikasi & file PDF otomatis', style: TextStyle(fontSize: 11)),
                      value: useAutomation,
                      activeColor: AppTheme.primaryBlue,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setStateDialog(() {
                          useAutomation = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: provider,
                      decoration: const InputDecoration(labelText: 'Penyedia Gateway (Provider)'),
                      items: const [
                        DropdownMenuItem(value: 'manual', child: Text('Manual (Tautan WA)')),
                        DropdownMenuItem(value: 'fonnte', child: Text('Fonnte (Otomatis)')),
                        DropdownMenuItem(value: 'wablas', child: Text('Wablas (Otomatis)')),
                      ],
                      onChanged: (val) {
                        setStateDialog(() {
                          provider = val ?? 'manual';
                        });
                      },
                    ),
                    if (provider != 'manual') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        decoration: const InputDecoration(
                          labelText: 'API Key / Token Otorisasi',
                          hintText: 'Masukkan token API gateway Anda',
                        ),
                      ),
                    ],
                    if (provider == 'wablas') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'Wablas Domain URL',
                          hintText: 'https://api.wablas.com',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('app_config').doc('whatsapp_config').set({
                      'provider': provider,
                      'useAutomation': useAutomation,
                      'apiToken': tokenController.text.trim(),
                      'gatewayUrl': urlController.text.trim(),
                    }, SetOptions(merge: true));
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Konfigurasi WhatsApp Gateway berhasil disimpan!')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Simpan', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChatBotSettingsDialog() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> data = {};
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('chat_config').get();
      if (doc.exists) {
        data = doc.data() ?? {};
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context);

    bool autoReplyEnabled = data['autoReplyEnabled'] ?? false;
    final textController = TextEditingController(
      text: data['autoReplyText'] ??
          'Halo! Terima kasih telah menghubungi KickDirty. Pesan Anda telah kami terima dan akan segera kami balas. Jam Operasional: 09:00 - 21:00.',
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Pengaturan Auto-Reply Chat'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Aktifkan Pesan Otomatis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Kirim salam otomatis ke pelanggan baru', style: TextStyle(fontSize: 11)),
                      value: autoReplyEnabled,
                      activeColor: AppTheme.primaryBlue,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setStateDialog(() {
                          autoReplyEnabled = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Isi Pesan Otomatis',
                        hintText: 'Tulis pesan balasan otomatis...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('app_config').doc('chat_config').set({
                      'autoReplyEnabled': autoReplyEnabled,
                      'autoReplyText': textController.text.trim(),
                    }, SetOptions(merge: true));
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pengaturan Auto-Reply Chat berhasil disimpan!')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Simpan', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

