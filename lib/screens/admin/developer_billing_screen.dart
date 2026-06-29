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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isCurrentMonthPaid ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isCurrentMonthPaid ? Colors.green.shade100 : Colors.red.shade100),
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
                          isCurrentMonthPaid ? 'LUNAS (Aplikasi Aktif)' : 'BELUM DIBAYAR (Aplikasi Terkunci)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isCurrentMonthPaid ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 38,
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
                            ),
                            child: Text(
                              isCurrentMonthPaid ? 'Batalkan Konfirmasi / Tandai Belum Lunas' : 'Konfirmasi Pembayaran / Tandai Lunas',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
