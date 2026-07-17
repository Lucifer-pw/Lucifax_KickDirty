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
import '../../utils/error_helper.dart';

class ProcessOrderScreen extends StatefulWidget {
  final bool isTab;
  ProcessOrderScreen({Key? key, this.isTab = false}) : super(key: key);

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
          title: Text('Input Estimasi Pengerjaan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Masukkan estimasi waktu pengerjaan untuk pesanan ini agar customer dapat melihatnya.'),
              SizedBox(height: 16),
              TextField(
                controller: estimationController,
                decoration: InputDecoration(
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
              child: Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, estimationController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: Text('Simpan'),
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
              title: Text('Konfirmasi Pembayaran (Wajib)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Customer belum membayar pesanan ini. Harap konfirmasi pembayaran dan ambil foto bukti pembayaran (EDC/Uang Tunai/Kuitansi) sebelum memproses pesanan.',
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 16),
                  if (tempPhotoBase64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildBase64Image(tempPhotoBase64!, 'Bukti Pembayaran', height: 120),
                    ),
                    SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final img = await ImageService.pickImageFromCamera(context: context);
                          if (img != null) {
                            setStateDialog(() {
                              tempPhotoBase64 = img;
                            });
                          }
                        },
                        icon: Icon(Icons.camera_alt),
                        label: Text('Kamera'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final img = await ImageService.pickImageFromGallery(context: context);
                          if (img != null) {
                            setStateDialog(() {
                              tempPhotoBase64 = img;
                            });
                          }
                        },
                        icon: Icon(Icons.photo),
                        label: Text('Galeri'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: tempPhotoBase64 == null
                      ? null
                      : () {
                          final sizeInBytes = (tempPhotoBase64!.length * 3 / 4).round();
                          if (sizeInBytes > 800 * 1024) {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                title: Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Ukuran Foto Terlalu Besar'),
                                  ],
                                ),
                                content: Text(
                                  'Ukuran bukti pembayaran adalah ${(sizeInBytes / 1024).toStringAsFixed(1)} KB.\n\n'
                                  'Batas maksimal adalah 800 KB agar dapat disimpan di database. Silakan gunakan foto lain.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            Navigator.pop(context, tempPhotoBase64);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: Text('Konfirmasi & Bayar'),
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

    try {
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
                  title: Text('Dokumentasi Hasil Cuci (After)'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ambil foto hasil cucian sepatu sebagai bukti sebelum diselesaikan. (Minimal 1 Foto)'),
                      SizedBox(height: 16),
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
                                    margin: EdgeInsets.only(right: 8),
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
                                      child: CircleAvatar(
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
                          child: Center(
                            child: Text(
                              'Belum ada foto diambil',
                              style: TextStyle(color: AppTheme.textGray, fontSize: 12),
                            ),
                          ),
                        ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final img = await ImageService.pickImageFromCamera(context: context);
                                if (img != null) {
                                  setStateDialog(() {
                                    capturedPhotos.add(img);
                                  });
                                }
                              },
                              icon: Icon(Icons.camera_alt),
                              label: Text('Kamera'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final img = await ImageService.pickImageFromGallery(context: context);
                                if (img != null) {
                                  setStateDialog(() {
                                    capturedPhotos.add(img);
                                  });
                                }
                              },
                              icon: Icon(Icons.photo),
                              label: Text('Galeri'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: Text('Batal'),
                    ),
                    ElevatedButton(
                      onPressed: capturedPhotos.isEmpty
                          ? null
                          : () {
                              int totalSize = capturedPhotos.fold(0, (sum, img) => sum + (img.length * 3 / 4).round());
                              if (totalSize > 850 * 1024) {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) => AlertDialog(
                                    title: Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                        SizedBox(width: 8),
                                        Text('Ukuran Total Terlalu Besar'),
                                      ],
                                    ),
                                    content: Text(
                                      'Total ukuran ${capturedPhotos.length} foto adalah ${(totalSize / 1024).toStringAsFixed(1)} KB.\n\n'
                                      'Batas maksimal total untuk semua foto adalah 850 KB agar dapat disimpan di database. '
                                      'Silakan hapus sebagian foto atau gunakan foto berukuran lebih kecil.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                Navigator.pop(context, capturedPhotos);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      child: Text('Simpan'),
                    ),
                  ],
                );
              },
            );
          },
        );

        if (photoAfterList == null || photoAfterList.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Foto After wajib diambil minimal 1 foto!')),
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
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Pembayaran Belum Lunas'),
                  ],
                ),
                content: Text(
                  'Sepatu tidak dapat diserahkan karena status pembayaran masih belum lunas. Silakan selesaikan pembayaran terlebih dahulu.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('OK'),
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
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('exceeds') || errorStr.contains('too large') || errorStr.contains('size') || errorStr.contains('limit')) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Ukuran Foto Terlalu Besar'),
                  ],
                ),
                content: Text(
                  'Gagal menyimpan karena ukuran foto yang Anda unggah terlalu besar (melebihi batas database).\n\n'
                  'Silakan pilih atau ambil kembali foto lain dengan resolusi lebih rendah.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateStatus(order);
                    },
                    child: Text('Pilih Ulang Foto'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Batal'),
                  ),
                ],
              );
            },
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memperbarui status: ${getCleanErrorMessage(e)}')),
          );
        }
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

    return StreamBuilder<List<OrderModel>>(
      stream: dbService.getOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text(getCleanErrorMessage(snapshot.error))));
        }

        final allOrders = snapshot.data ?? [];
        
        // Filter active orders based on tabs (ignore status 'diambil' in active process screen)
        final ordersDiBayar = allOrders.where((o) => o.status == 'dibayar').toList();
        final ordersDiterima = allOrders.where((o) => o.status == 'diterima').toList();
        final ordersDiproses = allOrders.where((o) => o.status == 'sedang_diproses').toList();
        final ordersSelesai = allOrders.where((o) => o.status == 'selesai').toList();

        Widget _buildTab(IconData icon, String text, int count) {
          return Tab(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 24),
                    if (count > 0)
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
                            '$count',
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
                SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 10)),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Proses Pesanan Aktif'),
            automaticallyImplyLeading: !widget.isTab,
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryBlue,
              unselectedLabelColor: AppTheme.textGray,
              indicatorColor: AppTheme.primaryBlue,
              tabs: [
                _buildTab(Icons.payments_outlined, 'Di Bayar', ordersDiBayar.length),
                _buildTab(Icons.receipt_long_outlined, 'Di Terima', ordersDiterima.length),
                _buildTab(Icons.engineering_outlined, 'Di Proses', ordersDiproses.length),
                _buildTab(Icons.check_circle_outline, 'Selesai', ordersSelesai.length),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOrderList(ordersDiBayar, 'dibayar'),
              _buildOrderList(ordersDiterima, 'diterima'),
              _buildOrderList(ordersDiproses, 'sedang_diproses'),
              _buildOrderList(ordersSelesai, 'selesai'),
            ],
          ),
        );
      },
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
            SizedBox(height: 16),
            Text(
              'Tidak ada pesanan di tahap ini',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textGray),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        
        // Date formatting: DD-MM-YYYY
        String day = order.createdAt.day.toString().padLeft(2, '0');
        String month = order.createdAt.month.toString().padLeft(2, '0');
        String year = order.createdAt.year.toString();
        String formattedDate = "$day-$month-$year";

        return Card(
          margin: EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Invoice Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.id,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                    ),
                    Text(
                      formattedDate,
                      style: TextStyle(color: AppTheme.textGray, fontSize: 12),
                    ),
                  ],
                ),
                Divider(height: 24, color: AppTheme.lightGray),

                // Customer Info
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 18, color: AppTheme.textGray),
                    SizedBox(width: 8),
                    Text(
                      order.customerName,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Spacer(),
                    // WhatsApp Shortcut icon
                    IconButton(
                      icon: Icon(Icons.chat_bubble_outline, color: Colors.green, size: 20),
                      onPressed: () => _sendWhatsAppMessage(order),
                      tooltip: 'Kirim notifikasi WA',
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Items list
                ...order.items.map((item) => Padding(
                      padding: EdgeInsets.only(left: 26, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.itemName} (${item.serviceName})',
                              style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText),
                            ),
                          ),
                          Text(
                            'Rp ${item.price.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),
                
                // Delivery/Logistic Details
                if (order.deliveryType == 'pickup_delivery') ...[
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        Icon(Icons.local_shipping_outlined, size: 16, color: AppTheme.primaryBlue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pengantaran: Kurir • Ongkir: Rp ${order.deliveryFee.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('app_config').doc('staff_permissions').snapshots(),
                          builder: (context, permSnap) {
                            final role = Provider.of<AuthService>(context, listen: false).currentUserModel?.role ?? 'staff';
                            if (role == 'owner' || role == 'developer') {
                              return IconButton(
                                icon: Icon(Icons.edit_outlined, size: 14, color: AppTheme.primaryBlue),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                onPressed: () => _showEditCourierFeeDialog(order),
                                tooltip: 'Ubah biaya ongkir',
                              );
                            }
                            final perms = (permSnap.data?.data() as Map<String, dynamic>?) ?? {};
                            if (perms['canEditCourierFee'] == true) {
                              return IconButton(
                                icon: Icon(Icons.edit_outlined, size: 14, color: AppTheme.primaryBlue),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                onPressed: () => _showEditCourierFeeDialog(order),
                                tooltip: 'Ubah biaya ongkir',
                              );
                            }
                            return SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 50, top: 2, right: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Alamat: ${order.deliveryAddress}',
                            style: TextStyle(fontSize: 11, color: AppTheme.textGray),
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
                            icon: Icon(Icons.map, size: 14, color: AppTheme.primaryBlue),
                            label: Text('Buka Maps', style: TextStyle(fontSize: 10, color: AppTheme.primaryBlue)),
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
                  SizedBox(height: 8),
                  Padding(
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
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Text(
                      'Catatan: "${order.notes}"',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange),
                    ),
                  ),
                ],
                if (order.voucherCode.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: order.voucherName.isNotEmpty
                        ? Row(
                            children: [
                              Icon(Icons.confirmation_number_outlined, size: 16, color: Colors.green),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Voucher: ${order.voucherCode} (${order.voucherName})${order.voucherDiscount > 0 ? " (-Rp ${order.voucherDiscount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")})" : ""}',
                                  style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          )
                        : FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('vouchers')
                                .where('code', isEqualTo: order.voucherCode)
                                .limit(1)
                                .get(),
                            builder: (context, snapshot) {
                              String displayText = order.voucherCode;
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                final doc = snapshot.data!.docs.first;
                                final name = doc.get('name') as String? ?? '';
                                if (name.isNotEmpty) {
                                  displayText = '${order.voucherCode} ($name)';
                                }
                              }
                              final discountSuffix = order.voucherDiscount > 0
                                  ? ' (-Rp ${order.voucherDiscount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")})'
                                  : '';
                              return Row(
                                children: [
                                  Icon(Icons.confirmation_number_outlined, size: 16, color: Colors.green),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Voucher: $displayText$discountSuffix',
                                      style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
                if (order.estimatedCompletion.isNotEmpty || order.status == 'sedang_diproses') ...[
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.orange),
                        SizedBox(width: 6),
                        Text(
                          order.estimatedCompletion.isEmpty
                              ? 'Belum ada estimasi'
                              : 'Estimasi: ${order.estimatedCompletion}',
                          style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                        ),
                        if (order.status == 'sedang_diproses' || order.status == 'diterima') ...[
                          SizedBox(width: 8),
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
                            child: Padding(
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
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Text(
                      'Bukti Transfer:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                    ),
                  ),
                  SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: _buildBase64Image(order.paymentProof, 'Bukti Transfer', height: 120),
                  ),
                ],

                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.only(left: 26),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Keseluruhan (Grand Total):',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                      ),
                      Text(
                        'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                      ),
                    ],
                  ),
                ),

                Divider(height: 24, color: AppTheme.lightGray),

                // Footer section with pricing, payment toggle, and transition buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Payment Toggle Button
                    InkWell(
                      onTap: () => _togglePayment(order),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            SizedBox(width: 4),
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
                         padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                         style: TextStyle(fontSize: 12),
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
            decoration: InputDecoration(
              labelText: 'Biaya Ongkir Kurir (Rp)',
              hintText: 'Contoh: 15000',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final double newFee = double.tryParse(feeController.text.trim()) ?? 0.0;
                
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => Center(child: CircularProgressIndicator()),
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
                      SnackBar(content: Text('Biaya ongkir & total invoice berhasil diperbarui!')),
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
              child: Text('Simpan', style: TextStyle(color: Colors.white)),
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
              insetPadding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(label, style: TextStyle(color: Colors.white)),
                    leading: IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
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
              errorBuilder: (context, error, stackTrace) => Center(
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
        child: Icon(Icons.broken_image, color: Colors.grey),
      );
    }
  }
}

