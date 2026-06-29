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
              Icon(Icons.qr_code_2, size: 64, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'QR Code Belum Tersedia',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      );
    }
    String cleanBase64 = base64Str;
    if (base64Str.contains(',')) {
      cleanBase64 = base64Str.split(',')[1];
    }
    try {
      final bytes = base64Decode(cleanBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          bytes,
          height: height,
          fit: BoxFit.contain,
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

  Future<void> _uploadPaymentProof(String monthCode) async {
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
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(monthCode)
          .set({
        'monthCode': monthCode,
        'amount': widget.amount,
        'dueDate': Timestamp.fromDate(widget.dueDate),
        'status': 'menunggu_konfirmasi',
        'paymentProof': image,
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
      if (mounted) setState(() => _isUploading = false);
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('developer_billing_invoices')
            .doc(currentMonthCode)
            .snapshots(),
        builder: (context, snapshot) {
          String status = 'belum_bayar';
          String paymentProof = '';

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
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
                            height: 45,
                            child: ElevatedButton.icon(
                              onPressed: _isUploading ? null : () => _uploadPaymentProof(currentMonthCode),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                              icon: const Icon(Icons.change_circle_outlined, color: Colors.white),
                              label: const Text('Ubah/Unggah Ulang Bukti', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ] else ...[
                          // Show QRIS and upload button
                          const Text(
                            'Scan QRIS di bawah ini untuk membayar:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkBlueText),
                          ),
                          const SizedBox(height: 12),
                          _buildBase64Image(widget.qrImage, height: 240),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 45,
                            child: ElevatedButton.icon(
                              onPressed: _isUploading ? null : () => _uploadPaymentProof(currentMonthCode),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                              icon: _isUploading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.upload_file_outlined, color: Colors.white),
                              label: Text(
                                _isUploading ? 'Mengunggah...' : 'Unggah Bukti Pembayaran',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
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
