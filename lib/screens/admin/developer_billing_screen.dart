import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/image_service.dart';
import '../../theme.dart';
import 'package:http/http.dart' as http;
import '../../utils/platform_helper.dart';
import '../../utils/error_helper.dart';
import '../../services/auto_backup_service.dart';
import '../chat_screen.dart';

class DeveloperBillingScreen extends StatefulWidget {
  DeveloperBillingScreen({Key? key}) : super(key: key);

  @override
  State<DeveloperBillingScreen> createState() => _DeveloperBillingScreenState();
}

class _DeveloperBillingScreenState extends State<DeveloperBillingScreen> {
  final _amountController = TextEditingController(text: '150000');
  final _gdriveUrlController = TextEditingController();
  final _restoreController = TextEditingController();
  DateTime _nextDueDate = DateTime(2026, 8, 1);
  String _lastPaidMonth = '';
  String _qrImageBase64 = '';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  double _selectedPresetAmount = -1.0;
  String _ownerSelectedPackageName = 'Belum memilih paket';
  double _ownerSelectedPackagePrice = 0.0;
  bool _enableOwnerLogs = false;

  // Auto backup config fields
  bool _enableAutoBackup = false;
  int _autoBackupHour = 2; // Default to 2 AM (Dini Hari)
  Timestamp? _lastAutoBackupTime;

  @override
  void initState() {
    super.initState();
    _loadBillingConfig();
    _loadDeveloperConfig();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _gdriveUrlController.dispose();
    _restoreController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    final double? val = double.tryParse(_amountController.text.trim());
    if (val == 100000.0 || val == 150000.0 || val == 250000.0) {
      if (_selectedPresetAmount != val) {
        setState(() {
          _selectedPresetAmount = val!;
        });
      }
    } else {
      if (_selectedPresetAmount != -1.0) {
        setState(() {
          _selectedPresetAmount = -1.0;
        });
      }
    }
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

      // Fetch owner's selected package from business_config
      final bizDoc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (bizDoc.exists) {
        final bizData = bizDoc.data();
        setState(() {
          _ownerSelectedPackageName = bizData?['selectedPackageName'] as String? ?? 'Belum memilih paket';
          _ownerSelectedPackagePrice = (bizData?['selectedPackagePrice'] as num?)?.toDouble() ?? 0.0;
        });
      }

      // Fetch activity log config
      final versionDoc = await FirebaseFirestore.instance.collection('app_config').doc('version_info').get();
      if (versionDoc.exists) {
        final versionData = versionDoc.data();
        setState(() {
          _enableOwnerLogs = versionData?['enableOwnerLogs'] == true;
        });
      }

      // Seed default packages if collection is empty
      await _seedDefaultPackages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat konfigurasi billing: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleOwnerLogs(bool val) async {
    setState(() {
      _enableOwnerLogs = val;
    });
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('version_info').set({
        'enableOwnerLogs': val,
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Akses log aktivitas owner berhasil ${val ? "diaktifkan" : "dinonaktifkan"}')),
        );
      }
    } catch (e) {
      setState(() {
        _enableOwnerLogs = !val;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui pengaturan: $e')),
        );
      }
    }
  }

  Future<void> _loadDeveloperConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('developer_config').get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            _gdriveUrlController.text = data['gdriveUrl'] as String? ?? '';
            _enableAutoBackup = data['enableAutoBackup'] == true;
            _autoBackupHour = data['autoBackupHour'] as int? ?? 2;
            _lastAutoBackupTime = data['lastAutoBackupTime'] as Timestamp?;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveDeveloperConfig() async {
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('developer_config').set({
        'gdriveUrl': _gdriveUrlController.text.trim(),
        'enableAutoBackup': _enableAutoBackup,
        'autoBackupHour': _autoBackupHour,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _onAutoBackupToggled(bool value) {
    setState(() {
      _enableAutoBackup = value;
    });
    _saveDeveloperConfig();
  }

  void _onAutoBackupHourChanged(int? value) {
    if (value != null) {
      setState(() {
        _autoBackupHour = value;
      });
      _saveDeveloperConfig();
    }
  }

  Future<void> _backupToGDrive() async {
    final url = _gdriveUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Masukkan URL Google Apps Script terlebih dahulu.')),
      );
      return;
    }

    setState(() {
      _isBackingUp = true;
    });

    try {
      await _saveDeveloperConfig();
      final backupData = await AutoBackupService.instance.generateBackupData();
      final payload = {
        'token': 'LucifaxKickDirtyBackupToken2026',
        'backupData': backupData,
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'text/plain'}, // Avoids CORS preflight OPTIONS request for Google Apps Script
        body: jsonEncode(payload),
      ).timeout(Duration(seconds: 45));

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup online berhasil! Tersimpan sebagai: ${resData['fileName']}')),
          );
        } else {
          throw Exception(resData['message'] ?? 'Gagal menyimpan.');
        }
      } else {
        throw Exception('Server merespon dengan status: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal Backup ke Google Drive: ${getCleanErrorMessage(e)}')),
      );
    } finally {
      setState(() {
        _isBackingUp = false;
      });
    }
  }

  Future<void> _backupLocalJson() async {
    setState(() {
      _isBackingUp = true;
    });

    try {
      final backupData = await AutoBackupService.instance.generateBackupData();
      final jsonString = jsonEncode(backupData);
      final fileName = 'backup_kickdirty_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';

      downloadBackupFile(jsonString, fileName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File backup JSON berhasil diunduh.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat backup lokal: ${getCleanErrorMessage(e)}')),
      );
    } finally {
      setState(() {
        _isBackingUp = false;
      });
    }
  }

  dynamic _deserializeTimestamps(dynamic value) {
    if (value is Map) {
      if (value['_type'] == 'Timestamp') {
        return Timestamp(value['seconds'] as int, value['nanoseconds'] as int);
      }
      final Map<String, dynamic> result = {};
      value.forEach((k, v) {
        result[k.toString()] = _deserializeTimestamps(v);
      });
      return result;
    } else if (value is List) {
      return value.map((item) => _deserializeTimestamps(item)).toList();
    }
    return value;
  }

  Future<void> _restoreFromJson() async {
    final jsonStr = _restoreController.text.trim();
    if (jsonStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tempelkan teks JSON backup terlebih dahulu.')),
      );
      return;
    }

    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('⚠️ PERINGATAN RESTORE'),
          content: Text(
            'Tindakan ini akan menimpa dan menulis ulang seluruh data di database Anda. '
            'Pastikan data backup Anda valid. Lanjutkan?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Ya, Timpa Data', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ) ?? false;

    if (!confirm) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      final Map<String, dynamic> backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      for (final col in backup.keys) {
        final List<dynamic> docs = backup[col] as List<dynamic>;
        for (final doc in docs) {
          final String id = doc['id'] as String;
          final Map<dynamic, dynamic> rawData = doc['data'] as Map;
          
          final Map<String, dynamic> data = {};
          rawData.forEach((k, v) {
            data[k.toString()] = _deserializeTimestamps(v);
          });

          await FirebaseFirestore.instance.collection(col).doc(id).set(data, SetOptions(merge: true));
        }
      }

      _restoreController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database berhasil di-restore sepenuhnya!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal restore database: ${getCleanErrorMessage(e)}')),
      );
    } finally {
      setState(() {
        _isRestoring = false;
      });
    }
  }

  Future<void> _saveBillingConfig() async {
    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nominal biaya maintenance tidak valid')),
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
          SnackBar(content: Text('Konfigurasi billing berhasil disimpan!')),
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

  Future<void> _confirmInvoicePaid(String docId, String monthCode) async {
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      
      // 1. Get the invoice doc to check durationMonths
      final invoiceDoc = await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(docId)
          .get();
      int durationMonths = 1;
      if (invoiceDoc.exists) {
        durationMonths = invoiceDoc.data()?['durationMonths'] as int? ?? 1;
      }

      // 2. Get current billing config to calculate next due date
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

      // 3. Calculate next due date (forcing day 1)
      DateTime baseDate = currentDueDate;
      if (baseDate.isBefore(now)) {
        baseDate = now;
      }
      final newDueDate = DateTime(baseDate.year, baseDate.month + durationMonths, 1);

      // 4. Update invoice document status to lunas
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(docId)
          .update({
        'status': 'lunas',
        'paidAt': Timestamp.fromDate(now),
      });

      // 5. Update main billing config lastPaidMonth and nextDueDate
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

  Future<void> _rejectInvoicePayment(String docId, String monthCode) async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(docId)
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
        child: Icon(Icons.qr_code_2, size: 64, color: Colors.grey),
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
        child: Icon(Icons.broken_image, size: 64, color: Colors.red),
      );
    }
  }

  Widget _buildBase64Image(String base64Str, {double height = 200}) {
    if (base64Str.isEmpty) return SizedBox();
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
      return Icon(Icons.broken_image, size: 48, color: Colors.red);
    }
  }

  void _showImageDialog(BuildContext context, String base64Str, String monthName) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bukti Bayar - $monthName',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _buildBase64Image(base64Str, height: 350),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatPackagePrice(num price) {
    return price.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  Future<void> _seedDefaultPackages({bool force = false}) async {
    try {
      if (!force) {
        final snapshot = await FirebaseFirestore.instance.collection('billing_packages').limit(1).get();
        if (snapshot.docs.isNotEmpty) return;
      }

      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('billing_packages');

      batch.set(col.doc('paket1'), {
        'name': 'Paket 1: Cloud Server & Backup Data',
        'price': 100000,
        'order': 1,
        'isHot': false,
        'features': [
          'Sewa Cloud Server Database Online 24/7',
          'Akses Website Portal Pelanggan Terintegrasi',
          'Penyimpanan Struk Digital & Foto Bukti Sepatu',
          'Backup Database Transaksi Harian (Aman & Terjamin)',
          'Pemeliharaan Dasar Keamanan Server (Security Rules)',
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(col.doc('paket2'), {
        'name': 'Paket 2: Pemeliharaan & Bantuan Teknis',
        'price': 150000,
        'order': 2,
        'isHot': false,
        'features': [
          'Semua Layanan Dasar Paket 1',
          'Garansi Kompatibilitas Pembaruan Sistem OS Android',
          'Bantuan Teknis Prioritas via WA (Troubleshooting)',
          'Bantuan Koneksi Printer Bluetooth Thermal Struk',
          'Update Minor Gratis (Ubah Teks Info/Harga Jasa)',
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(col.doc('paket3'), {
        'name': 'Paket 3: Premium + Domain Kustom (.COM / .ID)',
        'price': 250000,
        'order': 3,
        'isHot': true,
        'features': [
          'Semua Layanan Pemeliharaan Paket 1 & 2',
          'Domain Kustom Pribadi Toko (Contoh: kickdirty.com / kickdirty.id)',
          'Gratis Biaya Domain dan Maintenance',
          'Instalasi SSL (Keamanan HTTPS Gembok Hijau Resmi)',
          'Prioritas Utama Respon Bantuan Teknis Developer 24/7',
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paket default berhasil disimpan!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan paket default: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPackageDialog({Map<String, dynamic>? existingData, String? docId}) {
    final nameCtrl = TextEditingController(text: existingData?['name'] as String? ?? '');
    final priceCtrl = TextEditingController(text: (existingData?['price'] as num?)?.toStringAsFixed(0) ?? '');
    final orderCtrl = TextEditingController(text: (existingData?['order'] as int?)?.toString() ?? '');
    final featuresCtrl = TextEditingController(
      text: (existingData?['features'] as List<dynamic>?)?.join('\n') ?? '',
    );
    bool isHot = existingData?['isHot'] == true;
    final isEditing = docId != null;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                isEditing ? 'Edit Paket' : 'Tambah Paket Baru',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nama Paket',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Harga / Bulan (Rp)',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: orderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Urutan Tampil (1, 2, 3, ...)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Tandai sebagai Rekomendasi (isHot)', style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText)),
                      value: isHot,
                      activeColor: AppTheme.primaryBlue,
                      onChanged: (val) => setDialogState(() => isHot = val),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: featuresCtrl,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: 'Fitur (1 baris = 1 fitur)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Batal', style: TextStyle(color: AppTheme.textGray)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final price = num.tryParse(priceCtrl.text.trim());
                    final order = int.tryParse(orderCtrl.text.trim());
                    if (name.isEmpty || price == null || order == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Nama, harga, dan urutan wajib diisi dengan benar.')),
                      );
                      return;
                    }
                    final features = featuresCtrl.text
                        .split('\n')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();

                    final data = {
                      'name': name,
                      'price': price,
                      'order': order,
                      'isHot': isHot,
                      'features': features,
                      'updatedAt': FieldValue.serverTimestamp(),
                    };

                    try {
                      if (isEditing) {
                        await FirebaseFirestore.instance.collection('billing_packages').doc(docId).update(data);
                      } else {
                        await FirebaseFirestore.instance.collection('billing_packages').add(data);
                      }
                      if (mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal menyimpan paket: $e')),
                        );
                      }
                    }
                  },
                  child: Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deletePackage(String docId, String name) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Hapus Paket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
          content: Text('Yakin ingin menghapus paket "$name"? Tindakan ini tidak dapat dibatalkan.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal', style: TextStyle(color: AppTheme.textGray)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance.collection('billing_packages').doc(docId).delete();
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Paket "$name" berhasil dihapus.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal menghapus paket: $e')),
                    );
                  }
                }
              },
              child: Text('Hapus', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentMonthCode = DateFormat('yyyy-MM').format(DateTime.now());
    // Periode saat ini dianggap LUNAS jika sekarang masih sebelum jatuh tempo (bayar dulu, pakai kemudian)
    final bool isCurrentMonthPaid = DateTime.now().isBefore(_nextDueDate);
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUserModel;
    final bool isDeveloperUser = user?.role == 'developer';

    return Scaffold(
      appBar: AppBar(
        title: Text('Developer Billing Panel'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.chat_outlined),
            tooltip: 'Chat dengan Owner/Staff',
            onPressed: () {
              final authService = Provider.of<AuthService>(context, listen: false);
              final user = authService.currentUserModel;
              if (user != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      customerId: 'dev_support',
                      customerName: 'Dev Support (Developer)',
                      customerPhone: 'Support System',
                      senderId: user.uid,
                      senderName: user.name,
                      isAdmin: false,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manajemen Billing Maintenance Aplikasi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Atur biaya maintenance bulanan untuk klien/owner. Jika belum ditandai Lunas setelah tanggal jatuh tempo, aplikasi Owner & Staff akan otomatis terkunci.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.4),
                  ),
                  // Info Paket Pilihan Owner saat ini
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paket Pilihan Owner Saat Ini:',
                          style: TextStyle(fontSize: 12, color: AppTheme.textGray, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          _ownerSelectedPackageName,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                        ),
                        if (_ownerSelectedPackagePrice > 0) ...[
                          SizedBox(height: 4),
                          Text(
                            'Tarif Dasar: Rp ${_ownerSelectedPackagePrice.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")} / Bulan',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 20),

                   // Dropdown Pilihan Paket
                   DropdownButtonFormField<double>(
                     value: _selectedPresetAmount,
                     decoration: InputDecoration(
                       labelText: 'Paket Maintenance',
                       border: OutlineInputBorder(),
                     ),
                     items: [
                       DropdownMenuItem(
                         value: 100000.0,
                         child: Text('Paket 1 (Rp 100.000 / Bulan)'),
                       ),
                       DropdownMenuItem(
                         value: 150000.0,
                         child: Text('Paket 2 (Rp 150.000 / Bulan)'),
                       ),
                       DropdownMenuItem(
                         value: 250000.0,
                         child: Text('Paket 3 (Rp 250.000 / Bulan)'),
                       ),
                       DropdownMenuItem(
                         value: -1.0,
                         child: Text('Kustom (Bebas Edit)'),
                       ),
                     ],
                     onChanged: (val) {
                       if (val != null) {
                         setState(() {
                           _selectedPresetAmount = val;
                           if (val != -1.0) {
                             _amountController.text = val.toStringAsFixed(0);
                           }
                         });
                       }
                     },
                   ),
                   SizedBox(height: 16),

                   // Input nominal biaya
                   TextField(
                     controller: _amountController,
                     keyboardType: TextInputType.number,
                     decoration: InputDecoration(
                       labelText: 'Biaya Maintenance Bulanan (Rp)',
                       prefixText: 'Rp ',
                     ),
                   ),
                   SizedBox(height: 16),

                  // Due Date Selection (Start date of billing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.calendar_month, color: AppTheme.primaryBlue),
                    title: Text('Jatuh Tempo Pembayaran', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                    subtitle: Text(
                      DateFormat('dd MMMM yyyy').format(_nextDueDate),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.darkBlueText),
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
                  Divider(),
                  SizedBox(height: 12),

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
                      padding: EdgeInsets.all(16),
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
                            style: TextStyle(fontSize: 12, color: AppTheme.textGray),
                          ),
                          SizedBox(height: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          if (!isCurrentMonthPaid && !isBillingActive) ...[
                            SizedBox(height: 4),
                            Text(
                              'Sistem kunci otomatis baru aktif pada jatuh tempo ${DateFormat('dd/MM/yyyy').format(_nextDueDate)}',
                              style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontStyle: FontStyle.italic),
                            ),
                          ],
                          SizedBox(height: 16),
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
                                padding: EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isCurrentMonthPaid ? 'Batalkan Konfirmasi / Tandai Belum Lunas' : 'Konfirmasi Pembayaran / Tandai Lunas',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })(),
                  SizedBox(height: 16),
                  Divider(),
                  SizedBox(height: 12),

                  // QR Code Upload Area
                  Text('QR Code Pembayaran (QRIS)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText)),
                  SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        _buildQRPreview(),
                        SizedBox(height: 12),
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
                              icon: Icon(Icons.camera_alt),
                              label: Text('Ambil Foto QR'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                            ),
                            SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final img = await ImageService.pickImageFromGallery();
                                if (img != null) {
                                  setState(() {
                                    _qrImageBase64 = img;
                                  });
                                }
                              },
                              icon: Icon(Icons.photo_library),
                              label: Text('Galeri QR'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Divider(),
                  SizedBox(height: 16),

                  // PACKAGE MANAGEMENT CRUD CARD
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.cardShadow,
                      border: Border.all(color: AppTheme.lightGray, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kelola Paket Layanan (CRUD)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tambah, edit, atau hapus paket layanan yang tersedia untuk Owner.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                        ),
                        SizedBox(height: 12),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('billing_packages')
                              .orderBy('order')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Center(child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                              ));
                            }
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                  children: [
                                    Text(
                                      'Belum ada paket di database.',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textGray),
                                    ),
                                    SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () => _seedDefaultPackages(force: true),
                                      icon: Icon(Icons.restore, size: 14),
                                      label: Text('Gunakan Paket Bawaan (Default)', style: TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final docs = snapshot.data!.docs;
                            return Column(
                              children: docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final name = data['name'] as String? ?? 'Tanpa Nama';
                                final price = data['price'] as num? ?? 0;
                                final order = data['order'] as int? ?? 0;
                                final isHot = data['isHot'] == true;
                                final features = (data['features'] as List<dynamic>?)?.cast<String>() ?? [];
                                return Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isHot 
                                        ? AppTheme.primaryBlue.withOpacity(0.05) 
                                        : (AppTheme.isDarkMode ? Colors.grey[850] : Colors.grey.shade50),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isHot ? AppTheme.primaryBlue.withOpacity(0.3) : AppTheme.lightGray, width: 0.5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      '#$order',
                                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                                    ),
                                                    SizedBox(width: 6),
                                                    if (isHot)
                                                      Container(
                                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text('HOT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                                      ),
                                                  ],
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  name,
                                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkBlueText),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Rp ${_formatPackagePrice(price)} / Bulan',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.edit, size: 20, color: AppTheme.primaryBlue),
                                            tooltip: 'Edit Paket',
                                            onPressed: () => _showPackageDialog(existingData: data, docId: doc.id),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete, size: 20, color: Colors.red),
                                            tooltip: 'Hapus Paket',
                                            onPressed: () => _deletePackage(doc.id, name),
                                          ),
                                        ],
                                      ),
                                      if (features.isNotEmpty) ...[
                                        SizedBox(height: 8),
                                        ...features.map((f) => Padding(
                                          padding: EdgeInsets.only(left: 8, bottom: 2),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('• ', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
                                              Expanded(child: Text(f, style: TextStyle(fontSize: 11, color: AppTheme.textGray))),
                                            ],
                                          ),
                                        )),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _showPackageDialog(),
                                icon: Icon(Icons.add, size: 16),
                                label: Text('Tambah Paket', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryBlue,
                                  side: BorderSide(color: AppTheme.primaryBlue),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _seedDefaultPackages(force: true),
                                icon: Icon(Icons.restart_alt, size: 16),
                                label: Text('Reset ke Default', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: BorderSide(color: Colors.orange),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Divider(),
                  SizedBox(height: 16),

                  // DEV FEATURE TOGGLES CARD
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.cardShadow,
                      border: Border.all(color: AppTheme.lightGray, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Developer Feature Access Toggles',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Aktifkan atau nonaktifkan fitur tambahan berikut untuk klien (Owner).',
                          style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                        ),
                        SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Log Aktivitas Karyawan (Owner)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkBlueText),
                          ),
                          subtitle: Text(
                            'Owner dapat melihat seluruh catatan log tindakan staff/karyawan.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                          ),
                          value: _enableOwnerLogs,
                          activeColor: AppTheme.primaryBlue,
                          onChanged: (val) {
                            _toggleOwnerLogs(val);
                          },
                        ),
                      ],
                    ),
                  ),
                  if (isDeveloperUser) ...[
                    SizedBox(height: 20),
                    // DEVELOPER DATABASE TOOLS (BACKUP & RESTORE)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: AppTheme.cardShadow,
                        border: Border.all(color: AppTheme.lightGray, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.storage, color: AppTheme.primaryBlue, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Developer Database Tools',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Ekspor/Impor seluruh koleksi database Firestore. Hanya untuk akun Developer.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                          ),
                          SizedBox(height: 16),
                          
                          // 1. Local Backup
                          Text(
                            '1. Penyimpanan Lokal (PC / Laptop)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _isBackingUp ? null : _backupLocalJson,
                            icon: _isBackingUp 
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(Icons.download, size: 16),
                            label: Text('Unduh Backup JSON (Lokal)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, 38),
                            ),
                          ),
                          SizedBox(height: 16),
                          
                          // 2. Online Backup (Google Drive)
                          Text(
                            '2. Penyimpanan Online (Google Drive)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                          ),
                          SizedBox(height: 8),
                          TextField(
                            controller: _gdriveUrlController,
                            decoration: InputDecoration(
                              labelText: 'Google Apps Script Web App URL',
                              hintText: 'https://script.google.com/macros/s/.../exec',
                              prefixIcon: Icon(Icons.link, size: 18),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            style: TextStyle(fontSize: 12),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _isBackingUp ? null : _backupToGDrive,
                            icon: _isBackingUp 
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(Icons.cloud_upload, size: 16),
                            label: Text('Kirim Backup ke Google Drive'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, 38),
                            ),
                          ),
                           SizedBox(height: 12),
                           Container(
                             padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                             decoration: BoxDecoration(
                               color: AppTheme.primaryBlue.withOpacity(0.05),
                               borderRadius: BorderRadius.circular(8),
                               border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15)),
                             ),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                   children: [
                                     Row(
                                       children: [
                                         Icon(Icons.sync, size: 18, color: AppTheme.primaryBlue),
                                         SizedBox(width: 6),
                                         Text(
                                           'Backup Otomatis (Google Drive)',
                                           style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                         ),
                                       ],
                                     ),
                                     Switch(
                                       value: _enableAutoBackup,
                                       onChanged: _onAutoBackupToggled,
                                       activeColor: AppTheme.primaryBlue,
                                     ),
                                   ],
                                 ),
                                 if (_enableAutoBackup) ...[
                                   SizedBox(height: 4),
                                   Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       Text(
                                         'Waktu Backup Harian:',
                                         style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                                       ),
                                       DropdownButton<int>(
                                         value: _autoBackupHour,
                                         items: List.generate(24, (i) {
                                            String label = '${i.toString().padLeft(2, '0')}:00';
                                            if (i == 0) label += ' (Tengah Malam)';
                                            if (i == 2) label += ' (Dini Hari - Rekomendasi)';
                                            return DropdownMenuItem(
                                              value: i,
                                              child: Text(label, style: TextStyle(fontSize: 11)),
                                            );
                                          }),
                                         onChanged: _onAutoBackupHourChanged,
                                         style: TextStyle(color: AppTheme.darkBlueText, fontSize: 11),
                                         underline: SizedBox(),
                                       ),
                                     ],
                                   ),
                                 ],
                                 SizedBox(height: 4),
                                 Text(
                                   'Terakhir Backup Otomatis: ${_lastAutoBackupTime == null ? "Belum Pernah" : DateFormat('dd MMM yyyy, HH:mm').format(_lastAutoBackupTime!.toDate())}',
                                   style: TextStyle(fontSize: 10, color: AppTheme.textGray, fontStyle: FontStyle.italic),
                                 ),
                               ],
                             ),
                           ),
                           SizedBox(height: 16),
                           
                           // 3. Restore Database
                          Text(
                            '3. Restore / Impor Database',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                          SizedBox(height: 8),
                          TextField(
                            controller: _restoreController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: 'Tempelkan (Paste) Teks JSON Backup di Sini',
                              hintText: '{\n  "users": [...],\n  "orders": [...]\n}',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.all(10),
                            ),
                            style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _isRestoring ? null : _restoreFromJson,
                            icon: _isRestoring 
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(Icons.settings_backup_restore, size: 16),
                            label: Text('Mulai Restore Database'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, 38),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 20),
                  Divider(),
                  SizedBox(height: 16),

                  // INVOICE HISTORY SECTION
                  Text(
                    'Riwayat Pembayaran & Konfirmasi',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('developer_billing_invoices')
                        .orderBy('monthCode', descending: true)
                        .snapshots(),
                    builder: (context, invSnap) {
                      if (!invSnap.hasData) {
                        return Center(child: CircularProgressIndicator());
                      }
                      final docs = invSnap.data!.docs;
                      if (docs.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Text(
                            'Belum ada invoice yang dibuat.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textGray, fontStyle: FontStyle.italic),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final docId = docs[index].id;
                          final monthCode = data['monthCode'] as String? ?? '';
                          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                          final status = data['status'] as String? ?? 'belum_bayar';
                          final paymentProof = data['paymentProof'] as String? ?? '';
                          final paidAt = (data['paidAt'] as Timestamp?)?.toDate();
                          final ownerName = data['ownerName'] as String? ?? '';
                          final ownerPhone = data['ownerPhone'] as String? ?? '';
                          final durationMonths = data['durationMonths'] as int? ?? 1;

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
                            margin: EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(monthName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                  SizedBox(height: 6),
                                  Text('Nominal: Rp $amountFormatted | Durasi: ${durationMonths == 12 ? "1 Tahun" : "$durationMonths Bulan"}', style: TextStyle(fontSize: 12)),
                                  if (paidAt != null)
                                    Text('Lunas Pada: ${DateFormat('dd/MM/yyyy HH:mm').format(paidAt)}', style: TextStyle(fontSize: 11, color: AppTheme.textGray)),
                                  if (ownerName.isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(top: 2.0),
                                      child: Text(
                                        'Dibayar Oleh: $ownerName${ownerPhone.isNotEmpty ? " ($ownerPhone)" : ""}',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                      ),
                                    ),
                                  if (paymentProof.isNotEmpty) ...[
                                    SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _showImageDialog(context, paymentProof, monthName),
                                          icon: Icon(Icons.receipt_long, size: 16),
                                          label: Text('Lihat Bukti Bayar', style: TextStyle(fontSize: 11)),
                                        ),
                                        if (status == 'menunggu_konfirmasi') ...[
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () => _rejectInvoicePayment(docId, monthCode),
                                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                child: Text('Tolak', style: TextStyle(fontSize: 11)),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => _confirmInvoicePaid(docId, monthCode),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                                ),
                                                child: Text('Konfirmasi Lunas', style: TextStyle(fontSize: 11, color: Colors.white)),
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

                  SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveBillingConfig,
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                      child: _isSaving
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text('Simpan Konfigurasi'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
