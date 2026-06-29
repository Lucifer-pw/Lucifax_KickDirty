import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
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
    _tabController = TabController(length: 4, vsync: this);
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

  Future<String?> _showUploadPaymentProofDialog() async {
    String? tempPhotoBase64;
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Konfirmasi Pembayaran (Wajib)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Customer belum membayar pesanan ini. Harap konfirmasi pembayaran dan ambil foto bukti pembayaran (EDC/Uang Tunai/Kuitansi) sebelum memproses pesanan.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (tempPhotoBase64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildBase64Image(tempPhotoBase64!, 'Bukti Pembayaran', height: 120),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final img = await ImageService.pickImageFromCamera();
                          if (img != null) {
                            setStateDialog(() {
                              tempPhotoBase64 = img;
                            });
                          }
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Kamera'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final img = await ImageService.pickImageFromGallery();
                          if (img != null) {
                            setStateDialog(() {
                              tempPhotoBase64 = img;
                            });
                          }
                        },
                        icon: const Icon(Icons.photo),
                        label: const Text('Galeri'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: tempPhotoBase64 == null
                      ? null
                      : () => Navigator.pop(context, tempPhotoBase64),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Konfirmasi & Bayar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateStatus(OrderModel order) async {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final orderId = order.id;
    final currentStatus = order.status;
    String nextStatus = '';
    String successMsg = '';

    if (currentStatus == 'dibayar') {
      // Require payment proof to transition to 'diterima'
      if (order.paymentStatus != 'sudah_bayar' || order.paymentProof.isEmpty) {
        final paymentProof = await _showUploadPaymentProofDialog();
        if (paymentProof == null) {
          return; // Batal
        }
        await dbService.updateOfflineOrderPayment(orderId, paymentProof);
      }

      nextStatus = 'diterima';
      successMsg = 'Pembayaran dikonfirmasi & pesanan diterima!';
      await dbService.updateOrderStatus(orderId, nextStatus);
      await dbService.updateOrderPaymentStatus(orderId, 'sudah_bayar');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
      return;
    } else if (currentStatus == 'diterima') {
      // If order is not paid yet (offline walk-in cases), require payment proof first
      if (order.paymentStatus != 'sudah_bayar' || order.paymentProof.isEmpty) {
        final paymentProof = await _showUploadPaymentProofDialog();
        if (paymentProof == null) {
          return; // Batal
        }
        // Save the payment proof and mark as paid in database
        await dbService.updateOfflineOrderPayment(orderId, paymentProof);
      }

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
      List<String>? photoAfterList = await showDialog<List<String>?>(
        context: context,
        builder: (context) {
          List<String> capturedPhotos = [];
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text('Dokumentasi Hasil Cuci (After)'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Ambil foto hasil cucian sepatu sebagai bukti sebelum diselesaikan. (Minimal 1 Foto)'),
                    const SizedBox(height: 16),
                    if (capturedPhotos.isNotEmpty)
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: capturedPhotos.length,
                          itemBuilder: (context, idx) {
                            return Stack(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: MemoryImage(base64Decode(capturedPhotos[idx].split(',')[1])),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 10,
                                  child: InkWell(
                                    onTap: () {
                                      setStateDialog(() {
                                        capturedPhotos.removeAt(idx);
                                      });
                                    },
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                )
                              ],
                            );
                          },
                         ),
                      )
                    else
                      Container(
                        height: 80,
                        width: double.infinity,
                        color: Colors.grey[100],
                        child: const Center(
                          child: Text(
                            'Belum ada foto diambil',
                            style: TextStyle(color: AppTheme.textGray, fontSize: 12),
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
                                  capturedPhotos.add(img);
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
                                  capturedPhotos.add(img);
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
                    child: const Text('Batal'),
                  ),
                  ElevatedButton(
                    onPressed: capturedPhotos.isEmpty
                        ? null
                        : () => Navigator.pop(context, capturedPhotos),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: const Text('Simpan'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (photoAfterList == null || photoAfterList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto After wajib diambil minimal 1 foto!')),
        );
        return;
      }

      nextStatus = 'selesai';
      successMsg = 'Servis sepatu selesai!';
      await dbService.updateOrderStatusWithPhoto(orderId, nextStatus, photoAfterList);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
      return;
    } else if (currentStatus == 'selesai') {
      if (order.paymentStatus == 'belum_bayar') {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Pembayaran Belum Lunas'),
                ],
              ),
              content: const Text(
                'Sepatu tidak dapat diserahkan karena status pembayaran masih belum lunas. Silakan selesaikan pembayaran terlebih dahulu.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
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
            Tab(icon: Icon(Icons.payments_outlined), text: 'Di Bayar'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Di Terima'),
            Tab(icon: Icon(Icons.engineering_outlined), text: 'Di Proses'),
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
          final ordersDiBayar = allOrders.where((o) => o.status == 'dibayar').toList();
          final ordersDiterima = allOrders.where((o) => o.status == 'diterima').toList();
          final ordersDiproses = allOrders.where((o) => o.status == 'sedang_diproses').toList();
          final ordersSelesai = allOrders.where((o) => o.status == 'selesai').toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildOrderList(ordersDiBayar, 'dibayar'),
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
              status == 'dibayar'
                  ? Icons.payments_outlined
                  : status == 'diterima'
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
                
                // Delivery/Logistic Details
                if (order.deliveryType == 'pickup_delivery') ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined, size: 16, color: AppTheme.primaryBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pengantaran: Kurir • Ongkir: Rp ${order.deliveryFee.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('app_config').doc('staff_permissions').snapshots(),
                          builder: (context, permSnap) {
                            final role = Provider.of<AuthService>(context, listen: false).currentUserModel?.role ?? 'staff';
                            if (role == 'owner') {
                              return IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primaryBlue),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showEditCourierFeeDialog(order),
                                tooltip: 'Ubah biaya ongkir',
                              );
                            }
                            final perms = (permSnap.data?.data() as Map<String, dynamic>?) ?? {};
                            if (perms['canEditCourierFee'] == true) {
                              return IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primaryBlue),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showEditCourierFeeDialog(order),
                                tooltip: 'Ubah biaya ongkir',
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 50, top: 2, right: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Alamat: ${order.deliveryAddress}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                          ),
                        ),
                        if (order.mapsLink.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(order.mapsLink);
                              try {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.map, size: 14, color: AppTheme.primaryBlue),
                            label: const Text('Buka Maps', style: TextStyle(fontSize: 10, color: AppTheme.primaryBlue)),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        Icon(Icons.storefront_outlined, size: 16, color: AppTheme.textGray),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tipe: Drop-Off & Ambil Sendiri',
                            style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
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

                if (order.paymentProof.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Text(
                      'Bukti Transfer:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: _buildBase64Image(order.paymentProof, 'Bukti Transfer', height: 120),
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
                       onPressed: () => _updateStatus(order),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: AppTheme.primaryBlue,
                         foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                       ),
                       icon: Icon(
                         status == 'dibayar'
                             ? Icons.check
                             : status == 'diterima'
                                 ? Icons.play_arrow
                                 : status == 'sedang_diproses'
                                     ? Icons.done
                                     : Icons.local_shipping,
                         size: 16,
                       ),
                       label: Text(
                         status == 'dibayar'
                             ? 'Konfirmasi'
                             : status == 'diterima'
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

  void _showEditCourierFeeDialog(OrderModel order) {
    final feeController = TextEditingController(text: order.deliveryFee.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Ongkir (${order.id})'),
          content: TextField(
            controller: feeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Biaya Ongkir Kurir (Rp)',
              hintText: 'Contoh: 15000',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final double newFee = double.tryParse(feeController.text.trim()) ?? 0.0;
                
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  // Fetch business config for discount value if redeemed
                  double discount = 0.0;
                  if (order.pointsRedeemed > 0) {
                    final configDoc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
                    if (configDoc.exists) {
                      discount = (configDoc.data()?['discountValue'] as num?)?.toDouble() ?? 25000.0;
                    } else {
                      discount = 25000.0;
                    }
                  }

                  // Calculate new total amount
                  double servicesTotal = order.items.fold(0.0, (sum, item) => sum + item.price);
                  double newTotal = servicesTotal + newFee - discount;
                  if (newTotal < 0) newTotal = 0.0;

                  // Update order in Firestore
                  await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
                    'deliveryFee': newFee,
                    'totalAmount': newTotal,
                  });

                  if (context.mounted) {
                    Navigator.pop(context); // Close loading
                    Navigator.pop(context); // Close dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Biaya ongkir & total invoice berhasil diperbarui!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Close loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal memperbarui ongkir: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBase64Image(String base64Str, String label, {double height = 110}) {
    try {
      String cleanBase64 = base64Str;
      if (base64Str.contains(',')) {
        cleanBase64 = base64Str.split(',')[1];
      }
      final bytes = base64Decode(cleanBase64);
      return GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.black.withOpacity(0.9),
              insetPadding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(label, style: const TextStyle(color: Colors.white)),
                    leading: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: InteractiveViewer(
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: height,
            width: 120,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.lightGray),
            ),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      return Container(
        height: height,
        width: 120,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
  }
}

