import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/in_app_notification_service.dart';
import '../../services/image_service.dart';
import '../../theme.dart';
import '../login_screen.dart';

class BillingBlockScreen extends StatefulWidget {
  final double amount;
  final DateTime dueDate;
  final String qrImage;

  const BillingBlockScreen({
    Key? key,
    required this.amount,
    required this.dueDate,
    required this.qrImage,
  }) : super(key: key);

  @override
  State<BillingBlockScreen> createState() => _BillingBlockScreenState();
}

class _BillingBlockScreenState extends State<BillingBlockScreen> {
  bool _isUploading = false;
  int _durationMonths = 1;

  Widget _buildBase64Image(String base64Str, {double height = 240}) {
    if (base64Str.isEmpty) {
      return Container(
        height: height,
        width: height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Belum ada gambar', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          base64Decode(base64Str),
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: height,
              width: double.infinity,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, size: 64, color: Colors.red),
            );
          },
        ),
      );
    } catch (_) {
      return Container(
        height: height,
        width: height,
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, size: 64, color: Colors.red),
      );
    }
  }

  Future<void> _uploadPaymentProof(double uploadAmount, int durationMonths) async {
    final String? image = await showModalBottomSheet<String?>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.primaryBlue),
                title: const Text('Kamera (Ambil Foto Bukti)'),
                onTap: () async {
                  final img = await ImageService.pickImageFromCamera();
                  if (context.mounted) Navigator.pop(context, img);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppTheme.primaryBlue),
                title: const Text('Galeri (Pilih Foto Bukti)'),
                onTap: () async {
                  final img = await ImageService.pickImageFromGallery();
                  if (context.mounted) Navigator.pop(context, img);
                },
              ),
            ],
          ),
        );
      },
    );

    if (image == null || image.isEmpty) return;

    setState(() => _isUploading = true);

    try {
      // Save/update the invoice in developer_billing_invoices
      final authService = Provider.of<AuthService>(context, listen: false);
      final ownerName = authService.currentUserModel?.name ?? 'Unknown Owner';
      final ownerPhone = authService.currentUserModel?.phoneNumber ?? '';
      final ownerUid = authService.currentUserModel?.uid ?? '';
      final String currentMonthCode = DateFormat('yyyy-MM').format(DateTime.now());

      // Query for an existing pending invoice to overwrite
      final pendingQuery = await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .where('ownerUid', isEqualTo: ownerUid)
          .where('status', isEqualTo: 'menunggu_konfirmasi')
          .limit(1)
          .get();

      String docId;
      if (pendingQuery.docs.isNotEmpty) {
        docId = pendingQuery.docs.first.id;
      } else {
        docId = FirebaseFirestore.instance.collection('developer_billing_invoices').doc().id;
      }

      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(docId)
          .set({
        'monthCode': currentMonthCode,
        'amount': uploadAmount,
        'dueDate': Timestamp.fromDate(widget.dueDate),
        'status': 'menunggu_konfirmasi',
        'paymentProof': image,
        'ownerName': ownerName,
        'ownerPhone': ownerPhone,
        'ownerUid': ownerUid,
        'durationMonths': durationMonths,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bukti pembayaran berhasil diunggah! Menunggu konfirmasi developer.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengunggah bukti bayar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentMonthCode = DateFormat('yyyy-MM').format(DateTime.now());
    final String monthName = DateFormat('MMMM yyyy').format(DateTime.now());

    final authService = Provider.of<AuthService>(context, listen: false);
    final String role = authService.currentUserModel?.role ?? 'staff';
    final bool isOwner = role == 'owner' || role == 'developer';

    final String formattedAmount = widget.amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    final String formattedDate = DateFormat('dd MMMM yyyy').format(widget.dueDate);

    final String ownerUid = authService.currentUserModel?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('developer_billing_invoices')
            .where('ownerUid', isEqualTo: ownerUid)
            .where('status', isEqualTo: 'menunggu_konfirmasi')
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          String status = 'belum_bayar';
          String paymentProof = '';

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>?;
            if (data != null) {
              status = data['status'] as String? ?? 'belum_bayar';
              paymentProof = data['paymentProof'] as String? ?? '';
            }
          }

          // If somehow the status becomes lunas under a race condition, show a success loader
          if (status == 'lunas') {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Pembayaran terkonfirmasi! Membuka aplikasi...'),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        status == 'menunggu_konfirmasi'
                            ? Icons.pending_actions_outlined
                            : Icons.lock_person_outlined,
                        size: 80,
                        color: status == 'menunggu_konfirmasi' ? Colors.orange : Colors.redAccent,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        status == 'menunggu_konfirmasi'
                            ? 'Menunggu Konfirmasi'
                            : 'Layanan Ditangguhkan',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkBlueText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        status == 'menunggu_konfirmasi'
                            ? (isOwner
                                ? 'Bukti pembayaran Anda untuk bulan $monthName telah dikirim ke Developer. Aplikasi akan otomatis terbuka begitu Developer memverifikasi transfer Anda.'
                                : 'Bukti pembayaran telah dikirim ke Developer. Aplikasi akan otomatis terbuka begitu Developer memverifikasi transfer dari Owner.')
                            : (isOwner
                                ? 'Masa aktif aplikasi Anda telah habis untuk bulan $monthName. Harap lakukan pembayaran biaya pemeliharaan bulanan (maintenance billing) untuk mengaktifkan kembali layanan.'
                                : 'Masa aktif aplikasi telah habis untuk bulan $monthName. Harap hubungi Owner toko untuk melakukan pembayaran maintenance agar aplikasi aktif kembali.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textGray,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: status == 'menunggu_konfirmasi' ? Colors.orange.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: status == 'menunggu_konfirmasi' ? Colors.orange.shade100 : Colors.red.shade100,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Biaya Maintenance:', style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText)),
                                Text(
                                  'Rp $formattedAmount',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: status == 'menunggu_konfirmasi' ? Colors.orange : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Jatuh Tempo:', style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText)),
                                Text(
                                  formattedDate,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Restrict billing actions based on role
                      if (!isOwner) ...[
                        if (status == 'menunggu_konfirmasi')
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.hourglass_empty, color: Colors.orange[800]),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Owner sudah mengunggah bukti pembayaran. Sedang menunggu persetujuan Developer.',
                                    style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.red[800]),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Pembayaran belum diselesaikan. Hanya Owner yang dapat melakukan pembayaran dan mengunggah bukti bayar.',
                                    style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ] else ...[
                        // Owner/Developer layout: Show QRIS and upload button
                        if (status == 'menunggu_konfirmasi') ...[
                          const Text(
                            'Bukti Transfer yang Anda Unggah:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                          ),
                          const SizedBox(height: 12),
                          _buildBase64Image(paymentProof, height: 220),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _isUploading ? null : () => _uploadPaymentProof(widget.amount, 1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                              icon: const Icon(Icons.change_circle_outlined, color: Colors.white),
                              label: const Text(
                                'Ubah/Unggah Ulang Bukti',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Show Duration selector
                          const Text(
                            'Pilih Durasi Berlangganan:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [1, 3, 6, 12].map((months) {
                              final isSel = _durationMonths == months;
                              final String label = months == 12 ? '1 Tahun' : '$months Bulan';
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _durationMonths = months;
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSel ? AppTheme.primaryBlue : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSel ? AppTheme.primaryBlue : Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSel ? Colors.white : AppTheme.darkBlueText,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          
                          // Calculate total amount based on duration and base price
                          () {
                            double baseAmount = widget.amount;
                            double calculatedAmount = baseAmount * _durationMonths;
                            if (_durationMonths == 12) {
                              if (baseAmount == 100000.0) {
                                calculatedAmount = 1000000.0;
                              } else if (baseAmount == 150000.0) {
                                calculatedAmount = 1500000.0;
                              } else if (baseAmount == 250000.0) {
                                calculatedAmount = 2500000.0;
                              }
                            }
                            final formattedCalculatedAmount = calculatedAmount.toStringAsFixed(0).replaceAllMapped(
                                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                  (Match m) => '${m[1]}.',
                                );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_durationMonths == 12) ...[
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green[200]!),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star, color: Colors.green, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Promo Tahunan Aktif! Hemat Rp ${(baseAmount * 12 - calculatedAmount).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")} (Gratis 2 Bulan)',
                                            style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.lightGray,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Total Tagihan Baru:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      Text('Rp $formattedCalculatedAmount', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Scan QRIS di bawah ini untuk membayar:',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkBlueText),
                                ),
                                const SizedBox(height: 12),
                                _buildBase64Image(widget.qrImage, height: 240),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: _isUploading ? null : () => _uploadPaymentProof(calculatedAmount, _durationMonths),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    ),
                                    icon: _isUploading
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.upload_file_outlined, color: Colors.white),
                                    label: Text(
                                      _isUploading ? 'Mengunggah...' : 'Unggah Bukti Pembayaran',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }(),
                        ],
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            InAppNotificationService.instance.stopListening();
                            await Provider.of<AuthService>(context, listen: false).signOut();
                            if (context.mounted) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (_) => const LoginScreen()),
                              );
                            }
                          },
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('Keluar dari Akun'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
