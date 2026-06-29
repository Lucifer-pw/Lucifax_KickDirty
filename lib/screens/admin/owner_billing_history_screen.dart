import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

class OwnerBillingHistoryScreen extends StatelessWidget {
  const OwnerBillingHistoryScreen({Key? key}) : super(key: key);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Billing Aplikasi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada riwayat pembayaran billing.',
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
              final paidAt = (data['paidAt'] as Timestamp?)?.toDate();
              final dueDate = (data['dueDate'] as Timestamp?)?.toDate();

              // Format Month name (e.g. "Agustus 2026")
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
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
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
                          const Text('Biaya Maintenance:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
                          Text(
                            'Rp $amountFormatted',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
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
                      if (status == 'lunas' && paidAt != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tanggal Lunas:', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
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
                              label: const Text('Lihat Foto', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
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
    );
  }
}
