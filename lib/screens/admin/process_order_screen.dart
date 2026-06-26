import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';

class ProcessOrderScreen extends StatefulWidget {
  const ProcessOrderScreen({Key? key}) : super(key: key);

  @override
  State<ProcessOrderScreen> createState() => _ProcessOrderScreenState();
}

class _ProcessOrderScreenState extends State<ProcessOrderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String orderId, String currentStatus) async {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    String nextStatus = '';
    String successMsg = '';

    if (currentStatus == 'diterima') {
      nextStatus = 'sedang_diproses';
      successMsg = 'Sepatu mulai diproses!';
    } else if (currentStatus == 'sedang_diproses') {
      nextStatus = 'selesai';
      successMsg = 'Servis sepatu selesai!';
    } else if (currentStatus == 'selesai') {
      nextStatus = 'diambil';
      successMsg = 'Sepatu telah diserahkan ke pelanggan!';
    }

    if (nextStatus.isNotEmpty) {
      await dbService.updateOrderStatus(orderId, nextStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
    }
  }

  Future<void> _togglePayment(OrderModel order) async {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    String nextPaymentStatus = order.paymentStatus == 'belum_bayar' ? 'sudah_bayar' : 'belum_bayar';
    await dbService.updateOrderPaymentStatus(order.id, nextPaymentStatus);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pembayaran diperbarui ke: ${nextPaymentStatus == "sudah_bayar" ? "Lunas" : "Belum Bayar"}')),
      );
    }
  }

  Future<void> _sendWhatsAppMessage(OrderModel order) async {
    String statusText = '';
    if (order.status == 'diterima') {
      statusText = 'telah kami terima dan segera diproses.';
    } else if (order.status == 'sedang_diproses') {
      statusText = 'sedang dalam proses pencucian/servis.';
    } else if (order.status == 'selesai') {
      statusText = 'telah SELESAI dan siap diambil.';
    } else if (order.status == 'diambil') {
      statusText = 'telah diambil. Terima kasih telah mempercayai kami!';
    }

    String paymentText = order.paymentStatus == 'sudah_bayar' ? 'Lunas' : 'Belum Lunas (Silakan lakukan pembayaran)';

    String message = 'Halo Kak *${order.customerName}*,\n\n'
        'Sepatu Anda dengan nomor invoice *${order.id}* $statusText\n'
        'Detail sepatu:\n'
        '${order.items.map((item) => '- ${item.itemName} (${item.serviceName})').join('\n')}\n\n'
        'Total Biaya: *Rp ${order.totalAmount.toStringAsFixed(0)}* (${paymentText})\n\n'
        'Powered by Lucifax';

    final uri = Uri.parse('https://wa.me/${order.customerPhone}?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proses Pesanan Aktif'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textGray,
          indicatorColor: AppTheme.primaryBlue,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Diterima'),
            Tab(icon: Icon(Icons.engineering_outlined), text: 'Diproses'),
            Tab(icon: Icon(Icons.check_circle_outline), text: 'Selesai'),
          ],
        ),
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: dbService.getOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allOrders = snapshot.data ?? [];
          
          // Filter active orders based on tabs (ignore status 'diambil' in active process screen)
          final ordersDiterima = allOrders.where((o) => o.status == 'diterima').toList();
          final ordersDiproses = allOrders.where((o) => o.status == 'sedang_diproses').toList();
          final ordersSelesai = allOrders.where((o) => o.status == 'selesai').toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildOrderList(ordersDiterima, 'diterima'),
              _buildOrderList(ordersDiproses, 'sedang_diproses'),
              _buildOrderList(ordersSelesai, 'selesai'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrderList(List<OrderModel> orders, String status) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              status == 'diterima'
                  ? Icons.receipt_long_outlined
                  : status == 'sedang_diproses'
                      ? Icons.engineering_outlined
                      : Icons.check_circle_outline,
              size: 64,
              color: AppTheme.textGray.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Tidak ada pesanan di tahap ini',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textGray),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        
        // Date formatting: DD-MM-YYYY
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
                // Invoice Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.id,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                    ),
                    Text(
                      formattedDate,
                      style: const TextStyle(color: AppTheme.textGray, fontSize: 12),
                    ),
                  ],
                ),
                const Divider(height: 24, color: AppTheme.lightGray),

                // Customer Info
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18, color: AppTheme.textGray),
                    const SizedBox(width: 8),
                    Text(
                      order.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Spacer(),
                    // WhatsApp Shortcut icon
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline, color: Colors.green, size: 20),
                      onPressed: () => _sendWhatsAppMessage(order),
                      tooltip: 'Kirim notifikasi WA',
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Items list
                ...order.items.map((item) => Padding(
                      padding: const EdgeInsets.only(left: 26, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.itemName} (${item.serviceName})',
                              style: const TextStyle(fontSize: 13, color: AppTheme.darkBlueText),
                            ),
                          ),
                          Text(
                            'Rp ${item.price.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),
                
                if (order.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(
                      'Catatan: "${order.notes}"',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange),
                    ),
                  ),
                ],

                const Divider(height: 24, color: AppTheme.lightGray),

                // Footer section with pricing, payment toggle, and transition buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Payment Toggle Button
                    InkWell(
                      onTap: () => _togglePayment(order),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: order.paymentStatus == 'sudah_bayar'
                              ? Colors.green.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              order.paymentStatus == 'sudah_bayar' ? Icons.check_circle : Icons.error,
                              color: order.paymentStatus == 'sudah_bayar' ? Colors.green : Colors.red,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              order.paymentStatus == 'sudah_bayar' ? 'LUNAS' : 'BELUM BAYAR',
                              style: TextStyle(
                                color: order.paymentStatus == 'sudah_bayar' ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Advance status button
                    ElevatedButton.icon(
                      onPressed: () => _updateStatus(order.id, order.status),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(
                        status == 'diterima'
                            ? Icons.play_arrow
                            : status == 'sedang_diproses'
                                ? Icons.done
                                : Icons.local_shipping,
                        size: 16,
                      ),
                      label: Text(
                        status == 'diterima'
                            ? 'Proses'
                            : status == 'sedang_diproses'
                                ? 'Selesai'
                                : 'Serahkan',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
