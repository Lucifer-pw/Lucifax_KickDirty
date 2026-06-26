import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';
import '../login_screen.dart';

class CustomerPortalScreen extends StatefulWidget {
  const CustomerPortalScreen({Key? key}) : super(key: key);

  @override
  State<CustomerPortalScreen> createState() => _CustomerPortalScreenState();
}

class _CustomerPortalScreenState extends State<CustomerPortalScreen> {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final dbService = Provider.of<DatabaseService>(context);

    final currentUser = authService.currentUserModel;
    final String phoneNumber = currentUser?.phoneNumber ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('KickDirty Pelanggan'),
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
      body: currentUser == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<OrderModel>>(
              // Query orders matching customer's WhatsApp number for seamless synchronization
              stream: dbService.getOrdersByPhone(phoneNumber),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
                }

                final allOrders = snapshot.data ?? [];

                // Filter Active vs Completed (Picked Up) orders
                final activeOrders = allOrders.where((o) => o.status != 'diambil').toList();
                final historyOrders = allOrders.where((o) => o.status == 'diambil').toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Card
                      _buildProfileCard(currentUser.name, currentUser.email, phoneNumber),
                      const SizedBox(height: 24),

                      // Active Orders (Real-time tracking)
                      Text('Lacak Cucian Sepatu (Real-Time)', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (activeOrders.isEmpty)
                        _buildEmptyState('Tidak ada sepatu yang sedang dicuci saat ini.')
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: activeOrders.length,
                          itemBuilder: (context, index) {
                            return _buildActiveOrderCard(activeOrders[index]);
                          },
                        ),
                      const SizedBox(height: 24),

                      // History Orders
                      Text('Riwayat Cucian Selesai', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (historyOrders.isEmpty)
                        _buildEmptyState('Belum ada riwayat pesanan selesai.')
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: historyOrders.length,
                          itemBuilder: (context, index) {
                            return _buildHistoryOrderCard(historyOrders[index]);
                          },
                        ),
                      const SizedBox(height: 32),
                      const Center(child: Watermark()),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfileCard(String name, String email, String phone) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('WA: +$phone', style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.lightBlueBackground.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline, color: AppTheme.textGray, size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderCard(OrderModel order) {
    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.id,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 15),
                ),
                Text(formattedDate, style: const TextStyle(color: AppTheme.textGray, fontSize: 11)),
              ],
            ),
            const Divider(height: 20, color: AppTheme.lightGray),

            // Item Details
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(item.serviceName, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                    ],
                  ),
                )),
            const Divider(height: 20, color: AppTheme.lightGray),

            // Payment and Total Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Biaya', style: TextStyle(color: AppTheme.textGray, fontSize: 10)),
                    Text(
                      'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.darkBlueText),
                    ),
                  ],
                ),
                // Payment Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: order.paymentStatus == 'sudah_bayar'
                        ? Colors.green.withOpacity(0.12)
                        : Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.paymentStatus == 'sudah_bayar' ? 'LUNAS' : 'BELUM BAYAR',
                    style: TextStyle(
                      color: order.paymentStatus == 'sudah_bayar' ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress Stepper Tracker
            _buildProgressStepper(order.status),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStepper(String currentStatus) {
    int currentStep = 0;
    if (currentStatus == 'diterima') currentStep = 0;
    if (currentStatus == 'sedang_diproses') currentStep = 1;
    if (currentStatus == 'selesai') currentStep = 2;

    return Row(
      children: [
        _buildStep(0, 'Diterima', currentStep >= 0),
        _buildLine(currentStep >= 1),
        _buildStep(1, 'Diproses', currentStep >= 1),
        _buildLine(currentStep >= 2),
        _buildStep(2, 'Selesai', currentStep >= 2),
      ],
    );
  }

  Widget _buildStep(int stepIndex, String title, bool isCompleted) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isCompleted ? AppTheme.primaryBlue : AppTheme.lightGray,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.circle,
              color: Colors.white,
              size: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
              color: isCompleted ? AppTheme.primaryBlue : AppTheme.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(bool isCompleted) {
    return Container(
      height: 2,
      width: 30,
      color: isCompleted ? AppTheme.primaryBlue : AppTheme.lightGray,
    );
  }

  Widget _buildHistoryOrderCard(OrderModel order) {
    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.done_all, color: Colors.green),
          ),
          title: Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.items.map((item) => item.itemName).join(', '),
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(formattedDate, style: const TextStyle(fontSize: 10, color: AppTheme.textGray)),
            ],
          ),
          trailing: Text(
            'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
