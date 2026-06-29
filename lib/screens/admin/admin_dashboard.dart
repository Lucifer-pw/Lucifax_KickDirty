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
import 'category_crud_screen.dart';
import 'voucher_crud_screen.dart';
import 'financial_report_screen.dart';
import 'admin_chat_list_screen.dart';
import 'sales_detail_screen.dart';
import 'developer_billing_screen.dart';
import 'billing_block_screen.dart';
import 'package:intl/intl.dart';

import 'settings_screen.dart';
import '../../services/in_app_notification_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _showNetProfit = false;
  Map<String, bool> _staffPerms = {};

  bool _hasPerm(String key, String? role) {
    if (role == 'owner' || role == 'developer') return true;
    return _staffPerms[key] == true;
  }

  @override
  void initState() {
    super.initState();
    // Run update check on dashboard load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUserModel != null) {
        InAppNotificationService.instance.startListening(
          context,
          authService.currentUserModel!.uid,
          authService.currentUserModel!.role,
        );
      }
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
    final String role = currentUser?.role ?? 'staff';
    final String roleLabel = role == 'developer'
        ? 'Developer'
        : (role == 'owner' ? 'Owner' : 'Staff');

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('developer_billing').doc('config').snapshots(),
      builder: (context, billingSnapshot) {
        bool isBlocked = false;
        double billingAmount = 150000.0;
        DateTime billingDueDate = DateTime(2026, 8, 1);
        String billingQr = '';

        if (billingSnapshot.hasData && billingSnapshot.data!.exists) {
          final bData = billingSnapshot.data!.data() as Map<String, dynamic>?;
          if (bData != null) {
            final nextDueDate = (bData['nextDueDate'] as Timestamp?)?.toDate();
            final lastPaidMonth = bData['lastPaidMonth'] as String? ?? '';
            billingAmount = (bData['amount'] as num?)?.toDouble() ?? 150000.0;
            billingQr = bData['qrImage'] as String? ?? '';
            if (nextDueDate != null) {
              billingDueDate = nextDueDate;
            }

            final now = DateTime.now();
            if (nextDueDate != null && (now.isAfter(nextDueDate) || now.isAtSameMomentAs(nextDueDate))) {
              final currentMonthCode = DateFormat('yyyy-MM').format(now);
              if (lastPaidMonth != currentMonthCode) {
                if (role == 'owner' || role == 'staff') {
                  isBlocked = true;
                }
              }
            }
          }
        }

        if (isBlocked) {
          return BillingBlockScreen(
            amount: billingAmount,
            dueDate: billingDueDate,
            qrImage: billingQr,
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('app_config')
              .doc('staff_permissions')
              .snapshots(),
          builder: (context, permSnapshot) {
        // Update permissions map in real-time
        if (permSnapshot.hasData && permSnapshot.data!.exists) {
          _staffPerms = Map<String, bool>.from(
            (permSnapshot.data!.data() as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, v == true)),
          );
        }

        final bool showServices = _hasPerm('canManageServices', role);

        final List<Widget> screens = [];
        final List<Map<String, dynamic>> navItems = [];

        // 1. Beranda
        screens.add(_buildDashboardHome(context, dbService, currentUser, roleLabel, role, navItems));
        navItems.add({'index': 0, 'icon': Icons.grid_view, 'label': 'Beranda'});

        // 2. Input
        screens.add(InputOrderScreen(isTab: true, onOrderSubmitted: () => _onTabTapped(0)));
        navItems.add({'index': 1, 'icon': Icons.add_shopping_cart, 'label': 'Input'});

        // 3. Proses
        screens.add(const ProcessOrderScreen(isTab: true));
        navItems.add({'index': 2, 'icon': Icons.sync_alt, 'label': 'Proses'});

        // 4. Pesan
        screens.add(const AdminChatListScreen(isTab: true));
        navItems.add({'index': 3, 'icon': Icons.chat_outlined, 'label': 'Pesan'});

        // 5. Layanan (Conditional)
        int indexCounter = 4;
        if (showServices) {
          screens.add(const CategoryCrudScreen());
          navItems.add({'index': indexCounter, 'icon': Icons.cleaning_services_outlined, 'label': 'Layanan'});
          indexCounter++;
        }

        // 6. Riwayat (Always Last!)
        screens.add(const HistoryOrdersScreen(isTab: true));
        navItems.add({'index': indexCounter, 'icon': Icons.history, 'label': 'Riwayat'});

        // Clamp index if tab was removed
        if (_currentIndex >= screens.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _currentIndex = 0);
          });
        }

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
              index: _currentIndex < screens.length ? _currentIndex : 0,
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
                    ...navItems.map((item) => _buildNavItem(
                          item['index'] as int,
                          item['icon'] as IconData,
                          item['label'] as String,
                        )),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  },
);
  }

  Widget _buildDashboardHome(BuildContext context, DatabaseService dbService, UserModel? currentUser, String roleLabel, String role, List<Map<String, dynamic>> navItems) {
    // Check if user has permission to see settings
    final bool canAccessSettings = role == 'owner' ||
        _hasPerm('canAccessBusinessSettings', role) ||
        _hasPerm('canAccessWhatsAppSettings', role) ||
        _hasPerm('canAccessChatBotSettings', role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KickDirty Dashboard'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
                );
              } else if (value == 'developer_billing') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DeveloperBillingScreen()),
                );
              } else if (value == 'logout') {
                InAppNotificationService.instance.stopListening();
                await Provider.of<AuthService>(context, listen: false).signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (canAccessSettings)
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: AppTheme.darkBlueText, size: 20),
                      SizedBox(width: 10),
                      Text('Pengaturan'),
                    ],
                  ),
                ),
              if (role == 'developer')
                const PopupMenuItem<String>(
                  value: 'developer_billing',
                  child: Row(
                    children: [
                      Icon(Icons.payment_outlined, color: AppTheme.darkBlueText, size: 20),
                      SizedBox(width: 10),
                      Text('Developer Billing'),
                    ],
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text('Logout', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
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

              final bool showSalesCards = _hasPerm('canViewSalesCards', role);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileBanner(currentUser?.name ?? 'Admin', roleLabel),
                    const SizedBox(height: 16),
                    
                    // Notification banner for new & running orders
                    if (newOrdersCount > 0 || activeOrdersCount > 0) ...[
                      GestureDetector(
                        onTap: () {
                          final prosesIndex = navItems.indexWhere((item) => item['label'] == 'Proses');
                          if (prosesIndex != -1) {
                            _onTabTapped(prosesIndex);
                          }
                        },
                        child: Container(
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
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Sales recap cards — conditionally shown
                    if (showSalesCards) ...[
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
                    ],

                    Text('Menu Navigasi', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildMenuGrid(role, navItems),
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
        // Check if user has permission to view sales detail
        final authService = Provider.of<AuthService>(context, listen: false);
        final role = authService.currentUserModel?.role ?? 'staff';
        if (!_hasPerm('canViewSalesDetail', role)) return;

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

  Widget _buildMenuGrid(String role, List<Map<String, dynamic>> navItems) {
    int getIndexFor(String label) {
      return navItems.indexWhere((item) => item['label'] == label);
    }

    // Define operational menu items
    final List<Map<String, dynamic>> menuItems = [
      {
        'title': 'Input Pesanan',
        'subtitle': 'Input cucian sepatu baru',
        'icon': Icons.add_shopping_cart,
        'color': Colors.blue,
        'onTap': () => _onTabTapped(getIndexFor('Input')),
        'permKey': null,
      },
      {
        'title': 'Proses Pesanan',
        'subtitle': 'Update cucian real-time',
        'icon': Icons.sync_alt,
        'color': Colors.orange,
        'onTap': () => _onTabTapped(getIndexFor('Proses')),
        'permKey': null,
      },
      {
        'title': 'Riwayat Transaksi',
        'subtitle': 'Invoice & Cetak PDF',
        'icon': Icons.history,
        'color': Colors.green,
        'onTap': () => _onTabTapped(getIndexFor('Riwayat')),
        'permKey': null,
      },
      {
        'title': 'Pesan Masuk',
        'subtitle': 'Chat dengan pelanggan',
        'icon': Icons.chat_outlined,
        'color': Colors.pink,
        'onTap': () => _onTabTapped(getIndexFor('Pesan')),
        'permKey': null,
      },
      {
        'title': 'Kelola Layanan',
        'subtitle': 'CRUD tarif & layanan',
        'icon': Icons.cleaning_services_outlined,
        'color': Colors.indigo,
        'onTap': () {
          final showServices = _hasPerm('canManageServices', role);
          if (showServices) {
            final idx = getIndexFor('Layanan');
            if (idx != -1) _onTabTapped(idx);
          }
        },
        'permKey': 'canManageServices',
      },
      {
        'title': 'Laporan Keuangan',
        'subtitle': 'Pemasukan & laba bersih',
        'icon': Icons.analytics_outlined,
        'color': Colors.purple,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FinancialReportScreen()),
          );
        },
        'permKey': 'canViewFinancialReport',
      },
      {
        'title': 'Kelola Voucher',
        'subtitle': 'Diskon & promo belanja',
        'icon': Icons.confirmation_number_outlined,
        'color': Colors.orange,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VoucherCrudScreen()),
          );
        },
        'permKey': 'canManageServices',
      },
    ];

    // Filter items based on permissions
    final visibleItems = menuItems.where((item) {
      final permKey = item['permKey'] as String?;
      if (permKey == null) return true;
      return _hasPerm(permKey, role);
    }).toList();

    // Build rows of 2
    final List<Widget> rows = [];
    for (int i = 0; i < visibleItems.length; i += 2) {
      final first = visibleItems[i];
      final hasSecond = i + 1 < visibleItems.length;

      rows.add(
        Row(
          children: [
            Expanded(
              child: _buildMenuButton(
                first['title'] as String,
                first['subtitle'] as String,
                first['icon'] as IconData,
                first['color'] as Color,
                first['onTap'] as VoidCallback,
              ),
            ),
            const SizedBox(width: 12),
            hasSecond
                ? Expanded(
                    child: _buildMenuButton(
                      visibleItems[i + 1]['title'] as String,
                      visibleItems[i + 1]['subtitle'] as String,
                      visibleItems[i + 1]['icon'] as IconData,
                      visibleItems[i + 1]['color'] as Color,
                      visibleItems[i + 1]['onTap'] as VoidCallback,
                    ),
                  )
                : const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < visibleItems.length) {
        rows.add(const SizedBox(height: 12));
      }
    }

    return Column(children: rows);
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

