import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/image_service.dart';
import '../../theme.dart';
import 'owner_billing_history_screen.dart';

class OwnerBillingPackageScreen extends StatefulWidget {
  OwnerBillingPackageScreen({super.key});

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
          color: AppTheme.isDarkMode ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
        ),
        child: Center(
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
        child: Icon(Icons.broken_image, size: 64, color: Colors.red),
      );
    }
  }

  Future<void> _uploadPaymentProof(BuildContext context, double amount, DateTime dueDate, String qrImage, int durationMonths) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final ownerName = authService.currentUserModel?.name ?? 'Unknown Owner';
    final ownerPhone = authService.currentUserModel?.phoneNumber ?? '';
    final ownerUid = authService.currentUserModel?.uid ?? '';

    final String? image = await showModalBottomSheet<String?>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.primaryBlue),
                title: Text('Kamera (Ambil Foto Bukti)'),
                onTap: () async {
                  final img = await ImageService.pickImageFromCamera();
                  if (context.mounted) Navigator.pop(context, img);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppTheme.primaryBlue),
                title: Text('Galeri (Pilih Foto Bukti)'),
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
        'amount': amount,
        'dueDate': Timestamp.fromDate(dueDate),
        'status': 'menunggu_konfirmasi',
        'paymentProof': image,
        'ownerName': ownerName,
        'ownerPhone': ownerPhone,
        'ownerUid': ownerUid,
        'durationMonths': durationMonths,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bukti pembayaran berhasil diunggah! Menunggu konfirmasi developer.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunggah bukti bayar: ${e.toString()}')),
      );
    }
  }

  void _showPaymentBottomSheet(BuildContext context, double baseAmount, DateTime dueDate, String qrImage) {
    int selectedMonths = 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final authService = Provider.of<AuthService>(context, listen: false);
        final ownerUid = authService.currentUserModel?.uid ?? '';

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('developer_billing_invoices')
              .where('ownerUid', isEqualTo: ownerUid)
              .where('status', isEqualTo: 'menunggu_konfirmasi')
              .limit(1)
              .snapshots(),
          builder: (context, snapshot) {
            String invoiceStatus = 'belum_bayar';
            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
              final iData = snapshot.data!.docs.first.data() as Map<String, dynamic>?;
              invoiceStatus = iData?['status'] as String? ?? 'belum_bayar';
            }

            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                double calculatedAmount = baseAmount * selectedMonths;
                if (selectedMonths == 12) {
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

                DateTime newDueDate = DateTime(dueDate.year, dueDate.month + selectedMonths, 1);
                final formattedNewDueDate = DateFormat('dd MMMM yyyy').format(newDueDate);

                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Pembayaran Maintenance Bulanan',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                        ),
                      ),
                      SizedBox(height: 20),

                      if (invoiceStatus != 'menunggu_konfirmasi') ...[
                        Text(
                          'Pilih Durasi Berlangganan:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                        ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [1, 3, 6, 12].map((months) {
                            final isSel = selectedMonths == months;
                            final String label = months == 12 ? '1 Tahun' : '$months Bulan';
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    selectedMonths = months;
                                  });
                                },
                                child: Container(
                                  margin: EdgeInsets.symmetric(horizontal: 4),
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSel 
                                        ? AppTheme.primaryBlue 
                                        : (AppTheme.isDarkMode ? Colors.grey[800] : Colors.grey[100]),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSel 
                                          ? AppTheme.primaryBlue 
                                          : (AppTheme.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
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
                        SizedBox(height: 16),
                        if (selectedMonths == 12) ...[
                          Container(
                            margin: EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.star, color: Colors.green, size: 16),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Promo Tahunan Aktif! Hemat Rp ${(baseAmount * 12 - calculatedAmount).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")} (Gratis 2 Bulan)',
                                    style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],

                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.lightGray,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Tagihan:', style: TextStyle(fontSize: 12, color: AppTheme.darkBlueText)),
                                Text(
                                  'Rp $formattedCalculatedAmount', 
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    color: AppTheme.isDarkMode ? AppTheme.secondaryBlue : AppTheme.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Jatuh Tempo Baru:', style: TextStyle(fontSize: 12, color: AppTheme.darkBlueText)),
                                Text(
                                  formattedNewDueDate, 
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      Center(
                        child: Text(
                          'Scan kode QRIS di bawah ini untuk transfer:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkBlueText),
                        ),
                      ),
                      SizedBox(height: 12),
                      Center(child: _buildBase64Image(qrImage, height: 200)),
                      SizedBox(height: 20),
                      if (invoiceStatus == 'menunggu_konfirmasi') ...[
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: Row(
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
                        SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _uploadPaymentProof(context, calculatedAmount, dueDate, qrImage, selectedMonths);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: invoiceStatus == 'menunggu_konfirmasi' ? Colors.orange : Colors.green,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                          icon: Icon(Icons.upload_file, color: Colors.white, size: 18),
                          label: Text(
                            invoiceStatus == 'menunggu_konfirmasi' ? 'Unggah Ulang Bukti Bayar' : 'Unggah Bukti Pembayaran',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                );
              },
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
              title: Text('Konfirmasi Pilihan Paket'),
              content: Text(
                'Apakah Anda yakin ingin memilih $packageName?\n\n'
                'Tagihan biaya baru Anda sebesar Rp ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")} / bulan '
                'akan aktif dan diverifikasi oleh Developer pada periode penagihan berikutnya.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: Text('Ya, Pilih', style: TextStyle(color: Colors.white)),
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
        title: Text('Status & Paket Layanan'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.history_edu_outlined),
            tooltip: 'Riwayat Pembayaran',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OwnerBillingHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('developer_billing').doc('config').snapshots(),
        builder: (context, billingSnapshot) {
          if (billingSnapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          double billingAmount = 150000.0;
          DateTime billingDueDate = DateTime(2026, 8, 1);
          String billingQr = '';
          if (billingSnapshot.hasData && billingSnapshot.data!.exists) {
            final bData = billingSnapshot.data!.data() as Map<String, dynamic>?;
            if (bData != null) {
              final nextDueDate = (bData['nextDueDate'] as Timestamp?)?.toDate();
              billingAmount = (bData['amount'] as num?)?.toDouble() ?? 150000.0;
              billingQr = bData['qrImage'] as String? ?? '';
              if (nextDueDate != null) {
                billingDueDate = nextDueDate;
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
              double activePrice = billingAmount;
              final cData = configSnapshot.hasData && configSnapshot.data!.exists
                  ? configSnapshot.data!.data() as Map<String, dynamic>?
                  : null;
              if (cData != null) {
                selectedPackage = cData['selectedPackage'] as String? ?? '';
                final double? presetPrice = (cData['selectedPackagePrice'] as num?)?.toDouble();
                if (presetPrice != null) {
                  activePrice = presetPrice;
                }
              }

              String activePackageLabel = cData?['selectedPackageName'] as String? ?? '';
              if (activePackageLabel.isEmpty) {
                if (activePrice == 100000.0) {
                  activePackageLabel = 'Paket 1: Paket Cloud Server';
                } else if (activePrice == 150000.0) {
                  activePackageLabel = 'Paket 2: Paket Pemeliharaan & Support';
                } else if (activePrice == 250000.0) {
                  activePackageLabel = 'Paket 3: Paket Premium (Domain Kustom)';
                } else {
                  activePackageLabel = 'Paket Kustom (Developer)';
                }
              }

              return SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Billing Status Card
                    Container(
                      padding: EdgeInsets.all(20),
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
                                  Text('Status Aplikasi', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                                  SizedBox(height: 4),
                                  Text(
                                    statusBillingText,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sisaHariColor),
                                  ),
                                ],
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          Divider(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 2.0),
                                child: Icon(Icons.dns_outlined, color: AppTheme.primaryBlue, size: 20),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Paket Terbayar Saat Ini:',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.2),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      activePackageLabel,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.darkBlueText,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 2.0),
                                child: Icon(Icons.event_note, color: Colors.indigo, size: 20),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Jatuh Tempo Berikutnya:',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.2),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      DateFormat('dd MMMM yyyy').format(billingDueDate),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.darkBlueText,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () => _showPaymentBottomSheet(context, activePrice, billingDueDate, billingQr),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                              icon: Icon(Icons.payment, color: Colors.white, size: 18),
                              label: Text(
                                'Bayar Tagihan Sekarang',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24),
                    Text(
                      'PILIHAN PAKET MAINTENANCE APLIKASI',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText, letterSpacing: 0.5),
                    ),
                    SizedBox(height: 12),

                    // Dynamic packages from Firestore
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('billing_packages')
                          .orderBy('order')
                          .snapshots(),
                      builder: (context, pkgSnapshot) {
                        if (pkgSnapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ));
                        }
                        if (!pkgSnapshot.hasData || pkgSnapshot.data!.docs.isEmpty) {
                          return Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'Belum ada paket tersedia.\nHubungi developer untuk setup.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppTheme.textGray, fontSize: 13),
                              ),
                            ),
                          );
                        }
                        final packages = pkgSnapshot.data!.docs;
                        return Column(
                          children: packages.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final packageKey = doc.id;
                            final name = data['name'] as String? ?? 'Paket';
                            final price = (data['price'] as num?)?.toDouble() ?? 0.0;
                            final features = List<String>.from(data['features'] ?? []);
                            final isHot = data['isHot'] == true;
                            final order = data['order'] as int? ?? 0;
                            return _buildPackageCard(
                              packageKey: packageKey,
                              name: name,
                              price: price,
                              isActive: activePrice == price,
                              isSelected: selectedPackage == packageKey || (selectedPackage.isEmpty && activePrice == price),
                              features: features,
                              isHot: isHot,
                            );
                          }).toList(),
                        );
                      },
                    ),
                    SizedBox(height: 16),
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
      margin: EdgeInsets.only(bottom: 16),
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
                padding: EdgeInsets.symmetric(vertical: 4),
                color: Colors.orange,
                child: Text(
                  'SANGAT DIREKOMENDASIKAN (BRANDING PROFESSIONAL)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(20.0),
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
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text('Aktif', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Rp $priceFormatted / bulan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  Divider(height: 20),
                  ...features.map((feature) => Padding(
                        padding: EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(fontSize: 12, color: AppTheme.darkBlueText, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      )),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: isSelected ? null : () => _selectPackage(packageKey, name, price),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: BorderSide(color: isSelected ? Colors.grey : AppTheme.primaryBlue, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: isSelected 
                            ? (AppTheme.isDarkMode ? Colors.grey[800] : Colors.grey.shade100) 
                            : Colors.transparent,
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
