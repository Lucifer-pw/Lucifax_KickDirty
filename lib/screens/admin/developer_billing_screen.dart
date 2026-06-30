import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/image_service.dart';
import '../../theme.dart';

class DeveloperBillingScreen extends StatefulWidget {
  const DeveloperBillingScreen({Key? key}) : super(key: key);

  @override
  State<DeveloperBillingScreen> createState() => _DeveloperBillingScreenState();
}

class _DeveloperBillingScreenState extends State<DeveloperBillingScreen> {
  final _amountController = TextEditingController(text: '150000');
  DateTime _nextDueDate = DateTime(2026, 8, 1);
  String _lastPaidMonth = '';
  String _qrImageBase64 = '';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadBillingConfig();
  }

  Future<void> _loadBillingConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('developer_billing').doc('config').get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            _amountController.text = (data['amount'] as num?)?.toDouble().toStringAsFixed(0) ?? '150000';
            _nextDueDate = (data['nextDueDate'] as Timestamp?)?.toDate() ?? DateTime(2026, 8, 1);
            _lastPaidMonth = data['lastPaidMonth'] as String? ?? '';
            _qrImageBase64 = data['qrImage'] as String? ?? '';
          });
        }
      } else {
        // Seed default config in state
        setState(() {
          _amountController.text = '150000';
          _nextDueDate = DateTime(2026, 8, 1);
          _lastPaidMonth = '';
          _qrImageBase64 = '';
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat konfigurasi billing: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBillingConfig() async {
    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal biaya maintenance tidak valid')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('developer_billing').doc('config').set({
        'amount': amount,
        'nextDueDate': Timestamp.fromDate(_nextDueDate),
        'lastPaidMonth': _lastPaidMonth,
        'qrImage': _qrImageBase64,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konfigurasi billing berhasil disimpan!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan konfigurasi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmInvoicePaid(String monthCode) async {
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      
      // 1. Get current billing config to calculate next due date
      final configDoc = await FirebaseFirestore.instance
          .collection('developer_billing')
          .doc('config')
          .get();

      DateTime currentDueDate = DateTime.now();
      if (configDoc.exists) {
        final nextDueDateStamp = configDoc.get('nextDueDate') as Timestamp?;
        if (nextDueDateStamp != null) {
          currentDueDate = nextDueDateStamp.toDate();
        }
      }

      // 2. Advance the next due date by 1 month
      DateTime newDueDate;
      if (currentDueDate.month == 12) {
        newDueDate = DateTime(currentDueDate.year + 1, 1, currentDueDate.day);
      } else {
        newDueDate = DateTime(currentDueDate.year, currentDueDate.month + 1, currentDueDate.day);
      }

      // 3. Update invoice document status to lunas
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(monthCode)
          .update({
        'status': 'lunas',
        'paidAt': Timestamp.fromDate(now),
      });

      // 4. Update main billing config lastPaidMonth and nextDueDate
      await FirebaseFirestore.instance
          .collection('developer_billing')
          .doc('config')
          .update({
        'lastPaidMonth': monthCode,
        'nextDueDate': Timestamp.fromDate(newDueDate),
      });

      setState(() {
        _lastPaidMonth = monthCode;
        _nextDueDate = newDueDate;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pembayaran bulan $monthCode berhasil dikonfirmasi lunas dan jatuh tempo diperbarui ke ${DateFormat('dd/MM/yyyy').format(newDueDate)}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal konfirmasi lunas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _rejectInvoicePayment(String monthCode) async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(monthCode)
          .update({
        'status': 'ditolak',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // If that month was marked paid, clear it from main config
      if (_lastPaidMonth == monthCode) {
        await FirebaseFirestore.instance
            .collection('developer_billing')
            .doc('config')
            .update({
          'lastPaidMonth': '',
        });
        setState(() {
          _lastPaidMonth = '';
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konfirmasi pembayaran untuk bulan $monthCode ditolak.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menolak konfirmasi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildQRPreview() {
    if (_qrImageBase64.isEmpty) {
      return Container(
        height: 180,
        width: 180,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Icon(Icons.qr_code_2, size: 64, color: Colors.grey),
      );
    }

    String cleanBase64 = _qrImageBase64;
    if (_qrImageBase64.contains(',')) {
      cleanBase64 = _qrImageBase64.split(',')[1];
    }
    try {
      final bytes = base64Decode(cleanBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          height: 180,
          width: 180,
          fit: BoxFit.contain,
        ),
      );
    } catch (_) {
      return Container(
        height: 180,
        width: 180,
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, size: 64, color: Colors.red),
      );
    }
  }

  Widget _buildBase64Image(String base64Str, {double height = 200}) {
    if (base64Str.isEmpty) return const SizedBox();
    String cleanBase64 = base64Str;
    if (base64Str.contains(',')) {
      cleanBase64 = base64Str.split(',')[1];
    }
    try {
      final bytes = base64Decode(cleanBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          height: height,
          fit: BoxFit.contain,
        ),
      );
    } catch (_) {
      return const Icon(Icons.broken_image, size: 48, color: Colors.red);
    }
  }

  void _showImageDialog(BuildContext context, String base64Str, String monthName) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bukti Bayar - $monthName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildBase64Image(base64Str, height: 350),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentMonthCode = DateFormat('yyyy-MM').format(DateTime.now());
    final bool isCurrentMonthPaid = _lastPaidMonth == currentMonthCode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Billing Panel'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manajemen Billing Maintenance Aplikasi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Atur biaya maintenance bulanan untuk klien/owner. Jika belum ditandai Lunas setelah tanggal jatuh tempo, aplikasi Owner & Staff akan otomatis terkunci.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // Input nominal biaya
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Biaya Maintenance Bulanan (Rp)',
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Due Date Selection (Start date of billing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month, color: AppTheme.primaryBlue),
                    title: const Text('Jatuh Tempo Pembayaran', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                    subtitle: Text(
                      DateFormat('dd MMMM yyyy').format(_nextDueDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.darkBlueText),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _nextDueDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() {
                          _nextDueDate = picked;
                        });
                      }
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Current Month Billing Status card
                  (() {
                    final now = DateTime.now();
                    final bool isBillingActive = now.isAfter(_nextDueDate) || now.isAtSameMomentAs(_nextDueDate);
                    
                    Color cardBgColor = Colors.red.shade50;
                    Color cardBorderColor = Colors.red.shade100;
                    Color statusColor = Colors.red;
                    String statusText = 'BELUM DIBAYAR (Aplikasi Terkunci)';
                    
                    if (isCurrentMonthPaid) {
                      cardBgColor = Colors.green.shade50;
                      cardBorderColor = Colors.green.shade100;
                      statusColor = Colors.green;
                      statusText = 'LUNAS (Aplikasi Aktif)';
                    } else if (!isBillingActive) {
                      cardBgColor = Colors.amber.shade50;
                      cardBorderColor = Colors.amber.shade100;
                      statusColor = Colors.amber.shade800;
                      statusText = 'BELUM DIBAYAR (Kunci Belum Aktif)';
                    }

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tagihan Bulan Ini (${DateFormat('MMMM yyyy').format(DateTime.now())}):',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textGray),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          if (!isCurrentMonthPaid && !isBillingActive) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Sistem kunci otomatis baru aktif pada jatuh tempo ${DateFormat('dd/MM/yyyy').format(_nextDueDate)}',
                              style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontStyle: FontStyle.italic),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  if (isCurrentMonthPaid) {
                                    _lastPaidMonth = ''; // Mark unpaid
                                  } else {
                                    _lastPaidMonth = currentMonthCode; // Mark paid
                                  }
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCurrentMonthPaid ? Colors.redAccent : Colors.green,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isCurrentMonthPaid ? 'Batalkan Konfirmasi / Tandai Belum Lunas' : 'Konfirmasi Pembayaran / Tandai Lunas',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })(),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // QR Code Upload Area
                  const Text('QR Code Pembayaran (QRIS)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText)),
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        _buildQRPreview(),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final img = await ImageService.pickImageFromCamera();
                                if (img != null) {
                                  setState(() {
                                    _qrImageBase64 = img;
                                  });
                                }
                              },
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Ambil Foto QR'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final img = await ImageService.pickImageFromGallery();
                                if (img != null) {
                                  setState(() {
                                    _qrImageBase64 = img;
                                  });
                                }
                              },
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Galeri QR'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  // INVOICE HISTORY SECTION
                  const Text(
                    'Riwayat Pembayaran & Konfirmasi',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('developer_billing_invoices')
                        .orderBy('monthCode', descending: true)
                        .snapshots(),
                    builder: (context, invSnap) {
                      if (!invSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = invSnap.data!.docs;
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Text(
                            'Belum ada invoice yang dibuat.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textGray, fontStyle: FontStyle.italic),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final monthCode = data['monthCode'] as String? ?? '';
                          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                          final status = data['status'] as String? ?? 'belum_bayar';
                          final paymentProof = data['paymentProof'] as String? ?? '';
                          final paidAt = (data['paidAt'] as Timestamp?)?.toDate();

                          DateTime parsedMonth = DateTime.now();
                          try {
                            final parts = monthCode.split('-');
                            parsedMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
                          } catch (_) {}
                          final monthName = DateFormat('MMMM yyyy').format(parsedMonth);

                          final amountFormatted = amount.toStringAsFixed(0).replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                (Match m) => '${m[1]}.',
                              );

                          Color statusColor = Colors.red;
                          String statusLabel = 'Belum Lunas';
                          if (status == 'lunas') {
                            statusColor = Colors.green;
                            statusLabel = 'Lunas';
                          } else if (status == 'menunggu_konfirmasi') {
                            statusColor = Colors.orange;
                            statusLabel = 'Menunggu Konfirmasi';
                          } else if (status == 'ditolak') {
                            statusColor = Colors.grey;
                            statusLabel = 'Ditolak';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(monthName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Nominal: Rp $amountFormatted', style: const TextStyle(fontSize: 12)),
                                  if (paidAt != null)
                                    Text('Lunas Pada: ${DateFormat('dd/MM/yyyy HH:mm').format(paidAt)}', style: const TextStyle(fontSize: 11, color: AppTheme.textGray)),
                                  if (paymentProof.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _showImageDialog(context, paymentProof, monthName),
                                          icon: const Icon(Icons.receipt_long, size: 16),
                                          label: const Text('Lihat Bukti Bayar', style: TextStyle(fontSize: 11)),
                                        ),
                                        if (status == 'menunggu_konfirmasi') ...[
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () => _rejectInvoicePayment(monthCode),
                                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                child: const Text('Tolak', style: TextStyle(fontSize: 11)),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => _confirmInvoicePaid(monthCode),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                                ),
                                                child: const Text('Konfirmasi Lunas', style: TextStyle(fontSize: 11, color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveBillingConfig,
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Simpan Konfigurasi'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
