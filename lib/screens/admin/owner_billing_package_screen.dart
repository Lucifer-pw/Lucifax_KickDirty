import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/image_service.dart';
import '../../theme.dart';
import 'owner_billing_history_screen.dart';

class OwnerBillingPackageScreen extends StatefulWidget {
  const OwnerBillingPackageScreen({super.key});

  @override
  State<OwnerBillingPackageScreen> createState() => _OwnerBillingPackageScreenState();
}

class _OwnerBillingPackageScreenState extends State<OwnerBillingPackageScreen> {

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

  Future<void> _uploadPaymentProof(BuildContext context, double amount, DateTime dueDate, String qrImage) async {
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

    try {
      final String currentMonthCode = DateFormat('yyyy-MM').format(DateTime.now());
      
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(currentMonthCode)
          .set({
        'monthCode': currentMonthCode,
        'amount': amount,
        'dueDate': Timestamp.fromDate(dueDate),
        'status': 'menunggu_konfirmasi',
        'paymentProof': image,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bukti pembayaran berhasil diunggah! Menunggu konfirmasi developer.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunggah bukti bayar: ${e.toString()}')),
      );
    }
  }

  void _showPaymentBottomSheet(BuildContext context, double amount, DateTime dueDate, String qrImage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final formattedAmount = amount.toStringAsFixed(0).replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]}.',
            );
        final formattedDate = DateFormat('dd MMMM yyyy').format(dueDate);
        final String currentMonthCode = DateFormat('yyyy-MM').format(DateTime.now());

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('developer_billing_invoices')
              .doc(currentMonthCode)
              .snapshots(),
          builder: (context, snapshot) {
            String invoiceStatus = 'belum_bayar';
            if (snapshot.hasData && snapshot.data!.exists) {
              final iData = snapshot.data!.data() as Map<String, dynamic>?;
              invoiceStatus = iData?['status'] as String? ?? 'belum_bayar';
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pembayaran Maintenance Bulanan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.lightGray,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tagihan Bulan Ini:', style: TextStyle(fontSize: 12)),
                            Text('Rp $formattedAmount', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Batas Jatuh Tempo:', style: TextStyle(fontSize: 12)),
                            Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Scan kode QRIS di bawah ini untuk transfer:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _buildBase64Image(qrImage, height: 200),
                  const SizedBox(height: 20),
                  if (invoiceStatus == 'menunggu_konfirmasi') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade100),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.hourglass_empty, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Bukti pembayaran sudah terkirim. Menunggu verifikasi Developer.',
                              style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _uploadPaymentProof(context, amount, dueDate, qrImage);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: invoiceStatus == 'menunggu_konfirmasi' ? Colors.orange : Colors.green,
                      ),
                      icon: const Icon(Icons.upload_file, color: Colors.white),
                      label: Text(
                        invoiceStatus == 'menunggu_konfirmasi' ? 'Unggah Ulang Bukti Bayar' : 'Unggah Bukti Pembayaran',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectPackage(String packageKey, String packageName, double price) async {
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Konfirmasi Pilihan Paket'),
              content: Text(
                'Apakah Anda yakin ingin memilih $packageName?\n\n'
                'Tagihan biaya baru Anda sebesar Rp ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")} / bulan '
                'akan aktif dan diverifikasi oleh Developer pada periode penagihan berikutnya.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Ya, Pilih', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm) return;

    try {
      await FirebaseFirestore.instance.collection('app_config').doc('business_config').set({
        'selectedPackage': packageKey,
        'selectedPackageName': packageName,
        'selectedPackagePrice': price,
        'packageUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pilihan $packageName berhasil diajukan! Developer akan menyesuaikan tagihan Anda.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih paket: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status & Paket Layanan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_edu_outlined),
            tooltip: 'Riwayat Pembayaran',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OwnerBillingHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('developer_billing').doc('config').snapshots(),
        builder: (context, billingSnapshot) {
          if (billingSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          double billingAmount = 150000.0;
          DateTime billingDueDate = DateTime(2026, 8, 1);
          String billingQr = '';
          String activePackageLabel = 'Paket 2: Pemeliharaan & Support';

          if (billingSnapshot.hasData && billingSnapshot.data!.exists) {
            final bData = billingSnapshot.data!.data() as Map<String, dynamic>?;
            if (bData != null) {
              final nextDueDate = (bData['nextDueDate'] as Timestamp?)?.toDate();
              billingAmount = (bData['amount'] as num?)?.toDouble() ?? 150000.0;
              billingQr = bData['qrImage'] as String? ?? '';
              if (nextDueDate != null) {
                billingDueDate = nextDueDate;
              }

              if (billingAmount == 100000.0) {
                activePackageLabel = 'Paket 1: Paket Cloud Server';
              } else if (billingAmount == 150000.0) {
                activePackageLabel = 'Paket 2: Paket Pemeliharaan & Support';
              } else if (billingAmount == 250000.0) {
                activePackageLabel = 'Paket 3: Paket Premium (Domain Kustom)';
              } else {
                activePackageLabel = 'Paket Kustom (Developer)';
              }
            }
          }

          // Calculate remaining billing days
          final now = DateTime.now();
          final startOfToday = DateTime(now.year, now.month, now.day);
          final startOfDue = DateTime(billingDueDate.year, billingDueDate.month, billingDueDate.day);
          final int sisaHari = startOfDue.difference(startOfToday).inDays;

          Color sisaHariColor = Colors.green;
          String statusBillingText = 'Layanan Aktif';
          if (sisaHari <= 0) {
            sisaHariColor = Colors.red;
            statusBillingText = 'Jatuh Tempo!';
          } else if (sisaHari <= 7) {
            sisaHariColor = Colors.orange;
            statusBillingText = 'Segera Jatuh Tempo';
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('app_config').doc('business_config').snapshots(),
            builder: (context, configSnapshot) {
              String selectedPackage = '';
              if (configSnapshot.hasData && configSnapshot.data!.exists) {
                final cData = configSnapshot.data!.data() as Map<String, dynamic>?;
                selectedPackage = cData?['selectedPackage'] as String? ?? '';
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Billing Status Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.cardShadow,
                        border: Border.all(color: AppTheme.lightGray),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Status Aplikasi', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                                  const SizedBox(height: 4),
                                  Text(
                                    statusBillingText,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sisaHariColor),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: sisaHariColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  sisaHari <= 0 ? 'Habis' : '$sisaHari Hari Lagi',
                                  style: TextStyle(color: sisaHariColor, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Icon(Icons.dns_outlined, color: AppTheme.primaryBlue, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Paket Terbayar Saat Ini:', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
                                    const SizedBox(height: 2),
                                    Text(activePackageLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.event_note, color: Colors.indigo, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Jatuh Tempo Berikutnya:', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
                                    const SizedBox(height: 2),
                                    Text(DateFormat('dd MMMM yyyy').format(billingDueDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 45,
                            child: ElevatedButton.icon(
                              onPressed: () => _showPaymentBottomSheet(context, billingAmount, billingDueDate, billingQr),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.payment, color: Colors.white, size: 18),
                              label: const Text('Bayar Tagihan Sekarang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Text(
                      'PILIHAN PAKET MAINTENANCE APLIKASI',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 12),

                    // Package 1 Card
                    _buildPackageCard(
                      packageKey: 'paket1',
                      name: 'Paket 1: Cloud Server & Backup Data',
                      price: 100000.0,
                      isActive: billingAmount == 100000.0,
                      isSelected: selectedPackage == 'paket1',
                      features: [
                        'Sewa Cloud Database Firebase Online 24/7',
                        'Akses Website Portal Pelanggan Terintegrasi',
                        'Penyimpanan Struk Digital & Foto Bukti Sepatu',
                        'Backup Database Transaksi Harian (Aman & Terjamin)',
                        'Pemeliharaan Dasar Keamanan Server (Security Rules)',
                      ],
                    ),

                    // Package 2 Card
                    _buildPackageCard(
                      packageKey: 'paket2',
                      name: 'Paket 2: Pemeliharaan & Bantuan Teknis',
                      price: 150000.0,
                      isActive: billingAmount == 150000.0,
                      isSelected: selectedPackage == 'paket2' || (selectedPackage.isEmpty && billingAmount == 150000.0),
                      features: [
                        'Semua Layanan Dasar Paket 1',
                        'Garansi Kompatibilitas Pembaruan Sistem OS Android',
                        'Bantuan Teknis Prioritas via WA (Troubleshooting)',
                        'Bantuan Koneksi Printer Bluetooth Thermal Struk',
                        'Update Minor Gratis (Ubah Teks Info/Harga Jasa)',
                      ],
                    ),

                    // Package 3 Card
                    _buildPackageCard(
                      packageKey: 'paket3',
                      name: 'Paket 3: Premium + Domain Kustom (.COM / .ID)',
                      price: 250000.0,
                      isActive: billingAmount == 250000.0,
                      isSelected: selectedPackage == 'paket3',
                      isHot: true,
                      features: [
                        'Semua Layanan Pemeliharaan Paket 1 & 2',
                        'Domain Kustom Pribadi Toko (Contoh: kickdirty.com / kickdirty.id)',
                        'Gratis Biaya Domain Tahunan Selama Berlangganan',
                        'Instalasi SSL (Keamanan HTTPS Gembok Hijau Resmi)',
                        'Prioritas Utama Respon Bantuan Teknis Developer 24/7',
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPackageCard({
    required String packageKey,
    required String name,
    required double price,
    required bool isActive,
    required bool isSelected,
    required List<String> features,
    bool isHot = false,
  }) {
    final priceFormatted = price.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(
          color: isSelected
              ? AppTheme.primaryBlue
              : (isHot ? Colors.orangeAccent.withOpacity(0.5) : AppTheme.lightGray),
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isHot)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.orange,
                child: const Text(
                  'SANGAT DIREKOMENDASIKAN (BRANDING PROFESSIONAL)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppTheme.primaryBlue : AppTheme.darkBlueText,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: const Text('Aktif', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rp $priceFormatted / bulan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  const Divider(height: 20),
                  ...features.map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                feature,
                                style: const TextStyle(fontSize: 12, color: AppTheme.darkBlueText, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: isSelected ? null : () => _selectPackage(packageKey, name, price),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: BorderSide(color: isSelected ? Colors.grey : AppTheme.primaryBlue, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: isSelected ? Colors.grey.shade100 : Colors.transparent,
                      ),
                      child: Text(
                        isSelected ? 'Paket Pilihan Anda' : 'Pilih Paket ini',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.textGray : AppTheme.primaryBlue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
