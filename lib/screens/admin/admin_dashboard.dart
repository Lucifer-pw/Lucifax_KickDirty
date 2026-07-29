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
import 'activity_logs_screen.dart';
import '../chat_screen.dart';
import 'printer_settings_screen.dart';
import '../../utils/printer/printer_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';

import 'settings_screen.dart';
import 'owner_billing_package_screen.dart';
import '../../services/in_app_notification_service.dart';
import '../../services/auto_backup_service.dart';
import '../../services/presence_service.dart';

class AdminDashboard extends StatefulWidget {
  AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _showNetProfit = false;
  Map<String, bool> _staffPerms = {};
  bool _isPrinterConnected = false;
  StreamSubscription<bool>? _printerSubscription;

  bool _hasPerm(String key, String? role) {
    if (role == 'owner' || role == 'developer') return true;
    return _staffPerms[key] == true;
  }

  void _initPrinterStatus() async {
    // Initial check
    final isConnected = await PrinterService.instance.isConnected();
    if (mounted) {
      setState(() {
        _isPrinterConnected = isConnected;
      });
    }
    
    // Listen to changes
    _printerSubscription = PrinterService.instance.connectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _isPrinterConnected = status;
        });
        
        // Show offline/online notification
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status ? 'Printer Thermal Terhubung (Online)' : 'Printer Thermal Terputus (Offline)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: status ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initPrinterStatus();
    // Run update check on dashboard load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUserModel != null) {
        PresenceService.instance.initialize(authService.currentUserModel!.uid);
        InAppNotificationService.instance.startListening(
          context,
          authService.currentUserModel!.uid,
          authService.currentUserModel!.role,
        );
        AutoBackupService.instance.startChecking(
          authService.currentUserModel!.role,
        );
      }
    });
  }

  @override
  void dispose() {
    _printerSubscription?.cancel();
    PresenceService.instance.stop();
    AutoBackupService.instance.stopChecking();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    await UpdateDialog.checkAndShow(context);
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Widget _buildNavItem(int index, IconData icon, String label, {int badgeCount = 0}) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppTheme.primaryBlue : AppTheme.textGray,
                  size: 24,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
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
        Map<String, dynamic>? bData;

        if (billingSnapshot.hasData && billingSnapshot.data!.exists) {
          bData = billingSnapshot.data!.data() as Map<String, dynamic>?;
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
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('app_config').doc('business_config').snapshots(),
            builder: (context, bizSnapshot) {
              double activeAmount = billingAmount;
              if (bizSnapshot.hasData && bizSnapshot.data!.exists) {
                final bizData = bizSnapshot.data!.data() as Map<String, dynamic>?;
                final selectedPrice = (bizData?['selectedPackagePrice'] as num?)?.toDouble();
                if (selectedPrice != null) {
                  activeAmount = selectedPrice;
                }
              }
              return BillingBlockScreen(
                amount: activeAmount,
                dueDate: billingDueDate,
                qrImage: billingQr,
              );
            },
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
        screens.add(_buildDashboardHome(context, dbService, currentUser, roleLabel, role, navItems, bData));
        navItems.add({'index': 0, 'icon': Icons.grid_view, 'label': 'Beranda'});

        // 2. Input
        screens.add(InputOrderScreen(isTab: true, onOrderSubmitted: () => _onTabTapped(0)));
        navItems.add({'index': 1, 'icon': Icons.add_shopping_cart, 'label': 'Input'});

        // 3. Proses
        screens.add(ProcessOrderScreen(isTab: true));
        navItems.add({'index': 2, 'icon': Icons.sync_alt, 'label': 'Proses'});

        // 4. Pesan
        screens.add(AdminChatListScreen(isTab: true));
        navItems.add({'index': 3, 'icon': Icons.chat_outlined, 'label': 'Pesan'});

        // 5. Layanan (Conditional)
        int indexCounter = 4;
        if (showServices) {
          screens.add(CategoryCrudScreen());
          navItems.add({'index': indexCounter, 'icon': Icons.cleaning_services_outlined, 'label': 'Layanan'});
          indexCounter++;
        }

        // 6. Riwayat (Always Last!)
        screens.add(HistoryOrdersScreen(isTab: true));
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
            bottomNavigationBar: StreamBuilder<List<OrderModel>>(
              stream: dbService.getOrders(),
              builder: (context, orderSnap) {
                final orders = orderSnap.data ?? [];
                final activeProcessCount = orders.where((o) =>
                    o.status == 'dibayar' || o.status == 'diterima' || o.status == 'sedang_diproses' || o.status == 'selesai').length;

                return StreamBuilder<QuerySnapshot>(
                  stream: currentUser != null
                      ? FirebaseFirestore.instance
                          .collection('chats')
                          .where('participants', arrayContains: currentUser.uid)
                          .snapshots()
                      : Stream.empty(),
                  builder: (context, chatSnap) {
                    int unreadChatCount = 0;
                    if (chatSnap.hasData) {
                      for (final doc in chatSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>? ?? {};
                        final unreadMap = data['unreadCount'] as Map<String, dynamic>? ?? {};
                        unreadChatCount += (unreadMap[currentUser!.uid] as int? ?? 0);
                      }
                    }

                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            ...navItems.map((item) {
                              final label = item['label'] as String;
                              int badge = 0;
                              if (label == 'Proses') badge = activeProcessCount;
                              if (label == 'Pesan') badge = unreadChatCount;
                              return _buildNavItem(
                                item['index'] as int,
                                item['icon'] as IconData,
                                label,
                                badgeCount: badge,
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  },
);
  }

  Widget _buildDashboardHome(BuildContext context, DatabaseService dbService, UserModel? currentUser, String roleLabel, String role, List<Map<String, dynamic>> navItems, Map<String, dynamic>? billingConfig) {
    // Check if user has permission to see settings
    final bool canAccessSettings = role == 'owner' ||
        _hasPerm('canAccessBusinessSettings', role) ||
        _hasPerm('canAccessWhatsAppSettings', role) ||
        _hasPerm('canAccessChatBotSettings', role);

    return Scaffold(
      appBar: AppBar(
        title: Text('KickDirty Dashboard'),
        actions: [
          StreamBuilder<bool>(
            stream: PrinterService.instance.connectionStatusStream,
            initialData: _isPrinterConnected,
            builder: (context, snapshot) {
              final connected = snapshot.data ?? false;
              return Tooltip(
                message: connected ? 'Printer Online' : 'Printer Offline',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        connected ? Icons.print : Icons.print_disabled,
                        color: connected ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        connected ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: connected ? Colors.green : Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('app_config').doc('version_info').snapshots(),
            builder: (context, snapshot) {
              final bool enableOwnerLogs = snapshot.hasData &&
                  snapshot.data!.exists &&
                  (snapshot.data!.data() as Map<String, dynamic>?)?['enableOwnerLogs'] == true;

              final bool showLogsMenu = role == 'developer' || (role == 'owner' && enableOwnerLogs);

              return PopupMenuButton<String>(
                icon: Icon(Icons.more_vert),
                onSelected: (value) async {
                  if (value == 'settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AdminSettingsScreen()),
                    );
                  } else if (value == 'printer_settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PrinterSettingsScreen(role: role)),
                    );
                  } else if (value == 'developer_billing') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DeveloperBillingScreen()),
                    );
                  } else if (value == 'activity_logs') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ActivityLogsScreen()),
                    );
                  } else if (value == 'dev_support') {
                    final user = currentUser;
                    if (user != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            customerId: 'dev_support',
                            customerName: 'Developer Support',
                            customerPhone: 'Support Chat',
                            senderId: user.uid,
                            senderName: user.name,
                            isAdmin: true,
                          ),
                        ),
                      );
                    }
                  } else if (value == 'logout') {
                    PresenceService.instance.stop();
                    InAppNotificationService.instance.stopListening();
                    await Provider.of<AuthService>(context, listen: false).signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => LoginScreen()),
                      );
                    }
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (canAccessSettings)
                    PopupMenuItem<String>(
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
                    PopupMenuItem<String>(
                      value: 'developer_billing',
                      child: Row(
                        children: [
                          Icon(Icons.payment_outlined, color: AppTheme.darkBlueText, size: 20),
                          SizedBox(width: 10),
                          Text('Developer Billing'),
                        ],
                      ),
                    ),
                  if (showLogsMenu)
                    PopupMenuItem<String>(
                      value: 'activity_logs',
                      child: Row(
                        children: [
                          Icon(Icons.history_toggle_off_outlined, color: AppTheme.darkBlueText, size: 20),
                          SizedBox(width: 10),
                          Text('Log Aktivitas Staff'),
                        ],
                      ),
                    ),
                  PopupMenuItem<String>(
                    value: 'printer_settings',
                    child: Row(
                      children: [
                        Icon(Icons.print_outlined, color: AppTheme.darkBlueText, size: 20),
                        SizedBox(width: 10),
                        Text('Printer Settings'),
                      ],
                    ),
                  ),
                  if (role == 'owner' || role == 'staff')
                    PopupMenuItem<String>(
                      value: 'dev_support',
                      child: Row(
                        children: [
                          Icon(Icons.contact_support_outlined, color: AppTheme.darkBlueText, size: 20),
                          SizedBox(width: 10),
                          Text('Hubungi Developer'),
                        ],
                      ),
                    ),
                  PopupMenuItem<String>(
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
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: dbService.getOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
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
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileBanner(currentUser?.name ?? 'Admin', roleLabel),
                    SizedBox(height: 16),
                    
                    if ((role == 'owner' || role == 'developer') && billingConfig != null) ...[
                      _buildBillingDashboardBanner(context, billingConfig),
                      SizedBox(height: 16),
                    ],

                    if (role == 'developer') ...[
                      _buildEmployeeStatusCard(role),
                      SizedBox(height: 16),
                    ],
                    
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
                          padding: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active, color: AppTheme.primaryBlue, size: 24),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (newOrdersCount > 0)
                                      Text(
                                        'Ada $newOrdersCount pesanan baru masuk!',
                                        style: TextStyle(
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
                      SizedBox(height: 16),
                    ],

                    // Sales recap cards — conditionally shown
                    if (showSalesCards) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _showNetProfit ? 'Rekap Keuntungan Bersih' : 'Rekap Penjualan (Lunas)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                          ),
                          Row(
                            children: [
                              Text('Laba Bersih', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
                              SizedBox(width: 4),
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
                      SizedBox(height: 12),
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
                      SizedBox(height: 24),
                      _buildVisualChart(displayRecaps['monthly'] ?? 0.0, displayRecaps['yearly'] ?? 0.0),
                      SizedBox(height: 24),
                    ],

                    Text('Menu Navigasi', style: Theme.of(context).textTheme.titleLarge),
                    SizedBox(height: 16),
                    _buildMenuGrid(role, navItems),
                    SizedBox(height: 32),
                    Center(child: Watermark()),
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
      padding: EdgeInsets.all(20),
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
            child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Halo, $name',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
        padding: EdgeInsets.all(16),
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
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isNegative ? Colors.red.withOpacity(0.1) : color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: isNegative ? Colors.red : color, size: 20),
                ),
                if (isNegative)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'RUGI',
                      style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, size: 18, color: color.withOpacity(0.5)),
              ],
            ),
            SizedBox(height: 12),
            Text(title, style: TextStyle(color: AppTheme.textGray, fontSize: 12)),
            SizedBox(height: 4),
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
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performa Bulanan vs Target Rata-Rata',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText),
          ),
          SizedBox(height: 16),
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
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Penjualan Bulan ini', style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}% dari rata-rata',
                style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 11),
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
            MaterialPageRoute(builder: (_) => FinancialReportScreen()),
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
            MaterialPageRoute(builder: (_) => VoucherCrudScreen()),
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
            SizedBox(width: 12),
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
                : Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < visibleItems.length) {
        rows.add(SizedBox(height: 12));
      }
    }

    return Column(children: rows);
  }

  Widget _buildMenuButton(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(16),
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
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            SizedBox(height: 16),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText)),
            SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingDashboardBanner(BuildContext context, Map<String, dynamic> billingConfig) {
    final nextDueDate = (billingConfig['nextDueDate'] as Timestamp?)?.toDate();
    if (nextDueDate == null) return SizedBox();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfDue = DateTime(nextDueDate.year, nextDueDate.month, nextDueDate.day);
    final int sisaHari = startOfDue.difference(startOfToday).inDays;

    Color bannerColor = Colors.green;
    Color textColor = Colors.white;
    String message = '';
    IconData icon = Icons.info_outline;

    if (sisaHari <= 0) {
      bannerColor = Colors.redAccent;
      message = '⚠️ Masa aktif billing Anda sudah habis! Segera bayar agar aplikasi tetap aktif.';
      icon = Icons.error_outline;
    } else if (sisaHari <= 7) {
      bannerColor = Colors.orange;
      message = '⚠️ Billing aplikasi akan habis dalam $sisaHari hari lagi (Jatuh tempo: ${DateFormat('dd/MM/yyyy').format(nextDueDate)}).';
      icon = Icons.warning_amber_outlined;
    } else {
      bannerColor = AppTheme.primaryBlue;
      message = 'ℹ️ Billing aplikasi aktif. Sisa $sisaHari hari lagi sebelum jatuh tempo berikutnya.';
      icon = Icons.dns_outlined;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OwnerBillingPackageScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bannerColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: bannerColor.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold, height: 1.4),
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, color: textColor, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeStatusCard(String role) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['owner', 'staff', 'developer'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        
        final userDocs = snapshot.data!.docs;
        
        // Map and determine online status
        final List<Map<String, dynamic>> employees = [];
        int activeCount = 0;
        
        for (var doc in userDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final lastSeenRaw = data['lastSeen'];
          DateTime? lastSeen;
          if (lastSeenRaw is Timestamp) {
            lastSeen = lastSeenRaw.toDate();
          } else if (lastSeenRaw is String) {
            lastSeen = DateTime.tryParse(lastSeenRaw);
          }
          
          final bool isOnlineRaw = data['isOnline'] == true;
          
          // Consider online if flag is true AND lastSeen is within 2 minutes
          final bool isOnline = isOnlineRaw && 
              lastSeen != null && 
              DateTime.now().difference(lastSeen).inMinutes <= 2;
              
          if (isOnline) {
            activeCount++;
          }
          
          employees.add({
            'name': data['name'] ?? 'Karyawan',
            'role': data['role'] ?? 'staff',
            'isOnline': isOnline,
            'lastSeen': lastSeen,
            'initial': (data['name'] as String? ?? 'K').isNotEmpty 
                ? (data['name'] as String)[0].toUpperCase() 
                : 'K',
          });
        }
        
        // Sort: online employees first, then by name
        employees.sort((a, b) {
          if (a['isOnline'] != b['isOnline']) {
            return a['isOnline'] ? -1 : 1;
          }
          return (a['name'] as String).compareTo(b['name'] as String);
        });

        final bool isDeveloper = role == 'developer';

        return Container(
          width: double.infinity,
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
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people_outline, color: AppTheme.primaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Status Karyawan',
                        style: TextStyle(
                          color: AppTheme.darkBlueText,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Text(
                      '$activeCount Aktif',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              
              // Horizontal employee list
              SizedBox(
                height: isDeveloper ? 96 : 76,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final emp = employees[index];
                    final isOnline = emp['isOnline'] as bool;
                    final lastSeen = emp['lastSeen'] as DateTime?;
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Avatar Stack
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isOnline 
                                    ? AppTheme.primaryBlue 
                                    : Colors.grey.shade200,
                                child: Text(
                                  emp['initial'],
                                  style: TextStyle(
                                    color: isOnline ? Colors.white : AppTheme.textGray,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green : Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          
                          // Name
                          Text(
                            emp['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isOnline ? AppTheme.darkBlueText : AppTheme.textGray,
                              fontSize: 11,
                              fontWeight: isOnline ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),

                          // Last Seen (Developer role only)
                          if (isDeveloper) ...[
                            const SizedBox(height: 2),
                            Text(
                              _formatLastSeen(lastSeen, isOnline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isOnline ? Colors.green.shade700 : AppTheme.textGray.withOpacity(0.8),
                                fontSize: 9.5,
                                fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatLastSeen(DateTime? lastSeen, bool isOnline) {
    if (isOnline) return 'Online';
    if (lastSeen == null) return 'Belum online';
    
    final difference = DateTime.now().difference(lastSeen);
    if (difference.inSeconds < 60) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}j lalu';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}h lalu';
    } else {
      return DateFormat('dd/MM HH:mm').format(lastSeen);
    }
  }

}

