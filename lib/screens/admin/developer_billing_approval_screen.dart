import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

class DeveloperBillingApprovalScreen extends StatefulWidget {
  const DeveloperBillingApprovalScreen({super.key});

  @override
  State<DeveloperBillingApprovalScreen> createState() => _DeveloperBillingApprovalScreenState();
}

class _DeveloperBillingApprovalScreenState extends State<DeveloperBillingApprovalScreen> {
  bool _isProcessing = false;

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
                _buildBase64Image(base64Str, height: 380),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _approvePayment(String monthCode, double amount) async {
    setState(() => _isProcessing = true);
    try {
      // 1. Get the invoice doc to check durationMonths
      final invoiceDoc = await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(monthCode)
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
      final today = DateTime.now();
      if (baseDate.isBefore(today)) {
        baseDate = today;
      }
      final newDueDate = DateTime(baseDate.year, baseDate.month + durationMonths, 1);

      // 4. Batch updates to ensure atomicity
      final batch = FirebaseFirestore.instance.batch();
      
      // Update invoice status to lunas
      final invoiceRef = FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(monthCode);
      batch.update(invoiceRef, {
        'status': 'lunas',
        'paidAt': FieldValue.serverTimestamp(),
      });

      // Update main billing config
      final configRef = FirebaseFirestore.instance
          .collection('developer_billing')
          .doc('config');
      batch.update(configRef, {
        'nextDueDate': Timestamp.fromDate(newDueDate),
        'lastPaidMonth': monthCode,
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pembayaran billing $monthCode berhasil disetujui! Jatuh tempo diperbarui ke ${DateFormat('dd/MM/yyyy').format(newDueDate)}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyetujui pembayaran: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectPayment(String monthCode) async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('developer_billing_invoices')
          .doc(monthCode)
          .update({
        'status': 'ditolak',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pembayaran billing $monthCode telah ditolak.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menolak pembayaran: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konfirmasi Billing Owner'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('developer_billing_invoices')
                .orderBy('monthCode', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada bukti pembayaran billing dari owner.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final monthCode = data['monthCode'] as String? ?? '';
                  final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                  final status = data['status'] as String? ?? 'belum_bayar';
                  final paymentProof = data['paymentProof'] as String? ?? '';
                  final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
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
                  String statusLabel = 'Belum Bayar';
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
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                monthName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.darkBlueText),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Jumlah Tagihan:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                              Text(
                                'Rp $amountFormatted',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Durasi Langganan:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                              Text(
                                durationMonths == 12 ? '1 Tahun' : '$durationMonths Bulan',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                              ),
                            ],
                          ),
                          if (dueDate != null) ...[
                             const SizedBox(height: 6),
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 const Text('Jatuh Tempo:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                                 Text(
                                   DateFormat('dd/MM/yyyy').format(dueDate),
                                   style: const TextStyle(fontSize: 12, color: AppTheme.darkBlueText),
                                 ),
                               ],
                             ),
                           ],
                           if (ownerName.isNotEmpty) ...[
                             const SizedBox(height: 6),
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 const Text('Dibayar Oleh:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                                 Text(
                                   '$ownerName${ownerPhone.isNotEmpty ? " ($ownerPhone)" : ""}',
                                   style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                 ),
                               ],
                             ),
                           ],
                          if (status == 'lunas' && paidAt != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Disetujui Tanggal:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                                Text(
                                  DateFormat('dd/MM/yyyy HH:mm').format(paidAt),
                                  style: const TextStyle(fontSize: 12, color: AppTheme.darkBlueText),
                                ),
                              ],
                            ),
                          ],
                          if (paymentProof.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Bukti Pembayaran:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                                TextButton.icon(
                                  onPressed: () => _showImageDialog(context, paymentProof, monthName),
                                  icon: const Icon(Icons.image_outlined, size: 16),
                                  label: const Text('Lihat Foto Bukti', style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                ),
                              ],
                            ),
                          ],
                          if (status == 'menunggu_konfirmasi') ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _showRejectConfirmation(monthCode),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  child: const Text('Tolak', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _showApproveConfirmation(monthCode, amount),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  child: const Text('Setujui', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
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
          if (_isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void _showApproveConfirmation(String monthCode, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Setujui Pembayaran?'),
        content: Text('Apakah Anda yakin bukti transfer untuk billing bulan $monthCode sudah valid dan dana telah diterima?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approvePayment(monthCode, amount);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Setujui'),
          ),
        ],
      ),
    );
  }

  void _showRejectConfirmation(String monthCode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tolak Pembayaran?'),
        content: Text('Apakah Anda yakin ingin menolak bukti transfer untuk billing bulan $monthCode ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectPayment(monthCode);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
  }
}
