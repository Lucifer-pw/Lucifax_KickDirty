import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/database_service.dart';
import '../../services/image_service.dart';
import '../../theme.dart';

class ProcessOrderScreen extends StatefulWidget {
  final bool isTab;
  const ProcessOrderScreen({Key? key, this.isTab = false}) : super(key: key);

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

  Future<String?> _showEstimationDialog(String initialEstimation) async {
    final estimationController = TextEditingController(text: initialEstimation.isEmpty ? '3 Hari' : initialEstimation);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Input Estimasi Pengerjaan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Masukkan estimasi waktu pengerjaan untuk pesanan ini agar customer dapat melihatnya.'),
              const SizedBox(height: 16),
              TextField(
                controller: estimationController,
                decoration: const InputDecoration(
                  labelText: 'Estimasi Pengerjaan',
                  hintText: 'Contoh: 2 Jam, 1 Hari, 3 Hari',
                  prefixIcon: Icon(Icons.access_time),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, estimationController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateStatus(String orderId, String currentStatus) async {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    String nextStatus = '';
    String successMsg = '';

    if (currentStatus == 'diterima') {
      final estimation = await _showEstimationDialog('');
      if (estimation == null || estimation.isEmpty) {
        return; // Batal
      }
      nextStatus = 'sedang_diproses';
      successMsg = 'Sepatu mulai diproses!';
      await dbService.updateOrderStatusWithEstimation(orderId, nextStatus, estimation);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
      return;
    } else if (currentStatus == 'sedang_diproses') {
      String? photoAfter = await showDialog<String?>(
        context: context,
        builder: (context) {
          String? capturedBase64;
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text('Dokumentasi Hasil Cuci (After)'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Ambil foto hasil cucian sepatu sebagai bukti sebelum diselesaikan.'),
                    const SizedBox(height: 16),
                    if (capturedBase64 != null)
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: MemoryImage(base64Decode(capturedBase64!.split(',')[1])),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final img = await ImageService.pickImageFromCamera();
                              if (img != null) {
                                setStateDialog(() {
                                  capturedBase64 = img;
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Kamera'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final img = await ImageService.pickImageFromGallery();
                              if (img != null) {
                                setStateDialog(() {
                                  capturedBase64 = img;
                                });
                              }
                            },
                            icon: const Icon(Icons.photo),
                            label: const Text('Galeri'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Lewati'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, capturedBase64),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                    child: const Text('Simpan'),
                  ),
                ],
              );
            },
          );
        },
      );

      nextStatus = 'selesai';
      successMsg = 'Servis sepatu selesai!';
      if (photoAfter != null) {
        await dbService.updateOrderStatusWithPhoto(orderId, nextStatus, [photoAfter]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
        }
        return;
      }
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
        'Powered by KickDirty';

    // Sanitize phone number (remove spaces, symbols, and convert 08xx to 628xx)
    String cleanPhone = order.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '62${cleanPhone.substring(1)}';
    }

    final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat membuka WhatsApp: $e')),
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
        automaticallyImplyLeading: !widget.isTab,
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
    final dbService = Provider.of<DatabaseService>(context, listen: false);
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
                if (order.estimatedCompletion.isNotEmpty || order.status == 'sedang_diproses') ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Text(
                          order.estimatedCompletion.isEmpty
                              ? 'Belum ada estimasi'
                              : 'Estimasi: ${order.estimatedCompletion}',
                          style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                        ),
                        if (order.status == 'sedang_diproses' || order.status == 'diterima') ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final newEst = await _showEstimationDialog(order.estimatedCompletion);
                              if (newEst != null && newEst.isNotEmpty) {
                                await dbService.updateOrderEstimation(order.id, newEst);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Estimasi diperbarui ke: $newEst')),
                                  );
                                }
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Icon(Icons.edit, size: 14, color: AppTheme.primaryBlue),
                            ),
                          ),
                        ],
                      ],
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
