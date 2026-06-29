import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/order_model.dart';
import '../../services/database_service.dart';
import '../../services/whatsapp_service.dart';
import '../../theme.dart';
import '../../widgets/invoice_detail_modal.dart';

class HistoryOrdersScreen extends StatefulWidget {
  final bool isTab;
  const HistoryOrdersScreen({Key? key, this.isTab = false}) : super(key: key);

  @override
  State<HistoryOrdersScreen> createState() => _HistoryOrdersScreenState();
}

class _HistoryOrdersScreenState extends State<HistoryOrdersScreen> {
  String _searchQuery = '';
  String _statusFilter = 'semua'; // 'semua' | 'diterima' | 'sedang_diproses' | 'selesai' | 'diambil'

  // Build A5 PDF Invoice Document
  pw.Document _buildPdfInvoiceDocument(OrderModel order, String shopName, String shopPhone) {
    final pdf = pw.Document();

    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Logo / Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        shopName.toUpperCase(),
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0D47A1')),
                      ),
                      pw.Text('Shoe Cleaning & Care Services', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('INVOICE', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.Text(order.id, style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 8),

              // Metadata
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PELANGGAN:', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      pw.Text(order.customerName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('WA: ${order.customerPhone}', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('TANGGAL: $formattedDate', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('STATUS: ${order.status.toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Items Table
              pw.Table(
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.grey300),
                  bottom: pw.BorderSide(width: 1, color: PdfColors.black),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Layanan / Sepatu', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Harga', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  // Table Body
                  ...order.items.map((item) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(item.itemName, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            pw.Text('(${item.serviceName})', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Rp ${item.price.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 8),

              // Total Summary and Notes
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left side: Catatan
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (order.notes.isNotEmpty) ...[
                          pw.Text('Catatan:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                          pw.SizedBox(height: 2),
                          pw.Text(order.notes, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.orange800)),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  // Right side: Price Summary
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Subtotal: Rp ${order.items.fold(0.0, (sum, item) => sum + item.price).toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 8)),
                      if (order.deliveryFee > 0)
                        pw.Text('Ongkir: Rp ${order.deliveryFee.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 8)),
                      if (order.voucherDiscount > 0)
                        pw.Text('Diskon Voucher: -Rp ${order.voucherDiscount.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green)),
                      if (order.pointsRedeemed > 0) ...[
                        // Calculate points discount dynamically
                        pw.Text(
                          'Diskon Poin: -Rp ${((order.items.fold(0.0, (sum, item) => sum + item.price) + order.deliveryFee - order.voucherDiscount) - order.totalAmount).clamp(0.0, double.infinity).toStringAsFixed(0)}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.green),
                        ),
                      ],
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'TOTAL: Rp ${order.totalAmount.toStringAsFixed(0)}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0D47A1')),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Footer Note (dynamic height, no Spacer)
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Terima kasih atas kunjungan Anda!', style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 2),
                    pw.Text('HP/WA: $shopPhone • $shopName', style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // Generate and print PDF invoice
  Future<void> _generatePdfInvoice(OrderModel order) async {
    String shopName = "KickDirty";
    String shopPhone = "6281328580511";
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (doc.exists) {
        shopName = doc.data()?['shopName'] ?? "KickDirty";
        shopPhone = doc.data()?['shopPhone'] ?? "6281328580511";
      }
    } catch (_) {}

    final pdf = _buildPdfInvoiceDocument(order, shopName, shopPhone);

    // Open print preview
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'invoice_${order.id}.pdf',
    );
  }

  // Share PDF invoice to WA or other apps
  Future<void> _sharePdfInvoice(OrderModel order) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Mengunggah & Mengirim PDF...', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );

    String shopName = "KickDirty";
    String shopPhone = "6281328580511";
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (doc.exists) {
        shopName = doc.data()?['shopName'] ?? "KickDirty";
        shopPhone = doc.data()?['shopPhone'] ?? "6281328580511";
      }
    } catch (_) {}

    try {
      final pdf = _buildPdfInvoiceDocument(order, shopName, shopPhone);
      final bytes = await pdf.save();
      final filename = '${order.id}_$shopName.pdf';

      // Upload and send via Gateway
      final fileUrl = await WhatsAppService.uploadPdfToTmpFiles(bytes, filename);
      if (fileUrl != null) {
        final message = 'Halo Kak *${order.customerName}*,\n\nBerikut terlampir dokumen invoice asli pesanan Anda *${order.id}*.';
        final success = await WhatsAppService.sendNotification(
          phone: order.customerPhone,
          message: message,
          fileUrl: fileUrl,
          filename: filename,
        );

        if (mounted) Navigator.pop(context); // Close loading

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invoice PDF berhasil dikirim otomatis ke WhatsApp pelanggan sebagai berkas dokumen asli!')),
            );
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context); // Close loading if failed

    // Fallback: system share sheet
    final pdf = _buildPdfInvoiceDocument(order, shopName, shopPhone);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'invoice_${order.id}.pdf',
    );
  }

  Future<void> _sendWhatsAppMessage(OrderModel order) async {
    String shopName = "KickDirty";
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (doc.exists) {
        shopName = doc.data()?['shopName'] ?? "KickDirty";
      }
    } catch (_) {}

    String statusText = '';
    if (order.status == 'diterima') {
      statusText = 'telah kami terima dan segera diproses.';
    } else if (order.status == 'sedang_diproses') {
      statusText = 'sedang dalam proses pencucian/servis.';
    } else if (order.status == 'selesai') {
      statusText = 'telah SELESAI dan siap diambil.';
    } else if (order.status == 'diambil') {
      statusText = 'telah diambil. Terima kasih atas kepercayaan Anda!';
    }

    String paymentText = order.paymentStatus == 'sudah_bayar' ? 'Lunas' : 'Belum Lunas';

    String message = 'Halo Kak *${order.customerName}*,\n\n'
        'Sepatu Anda dengan nomor invoice *${order.id}* $statusText\n'
        'Detail sepatu:\n'
        '${order.items.map((item) => '- ${item.itemName} (${item.serviceName})').join('\n')}\n\n'
        'Total Biaya: *Rp ${order.totalAmount.toStringAsFixed(0)}* (${paymentText})\n\n'
        'Powered by $shopName';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        automaticallyImplyLeading: !widget.isTab,
      ),
      body: Column(
        children: [
          // Filter & Search Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Search field
                TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Cari nama atau nomor WA...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppTheme.lightBlueBackground.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('semua', 'Semua'),
                      const SizedBox(width: 8),
                      _buildFilterChip('diterima', 'Diterima'),
                      const SizedBox(width: 8),
                      _buildFilterChip('sedang_diproses', 'Diproses'),
                      const SizedBox(width: 8),
                      _buildFilterChip('selesai', 'Selesai'),
                      const SizedBox(width: 8),
                      _buildFilterChip('diambil', 'Diambil'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: StreamBuilder<List<OrderModel>>(
              stream: dbService.getOrders(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var orders = snapshot.data ?? [];

                // Filter by Search Query
                if (_searchQuery.isNotEmpty) {
                  orders = orders.where((o) {
                    return o.customerName.toLowerCase().contains(_searchQuery) ||
                        o.customerPhone.contains(_searchQuery) ||
                        o.id.toLowerCase().contains(_searchQuery);
                  }).toList();
                }

                // Filter by Status
                if (_statusFilter != 'semua') {
                  orders = orders.where((o) => o.status == _statusFilter).toList();
                }

                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history_toggle_off, size: 64, color: AppTheme.textGray),
                        const SizedBox(height: 16),
                        Text(
                          'Tidak ada riwayat pesanan',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textGray),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];

                    // Date formatting: DD-MM-YYYY
                    String day = order.createdAt.day.toString().padLeft(2, '0');
                    String month = order.createdAt.month.toString().padLeft(2, '0');
                    String year = order.createdAt.year.toString();
                    String formattedDate = "$day-$month-$year";

                    // Determine Status Color
                    Color statusColor = Colors.grey;
                    if (order.status == 'diterima') statusColor = Colors.orange;
                    if (order.status == 'sedang_diproses') statusColor = AppTheme.primaryBlue;
                    if (order.status == 'selesai') statusColor = Colors.teal;
                    if (order.status == 'diambil') statusColor = Colors.green;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => InvoiceDetailModal.show(context, order),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    order.id,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      order.status.toUpperCase().replaceAll('_', ' '),
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20, color: AppTheme.lightGray),
                              
                              Text(
                                'Pelanggan: ${order.customerName}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text('Tanggal: $formattedDate', style: const TextStyle(color: AppTheme.textGray, fontSize: 11)),
                              const SizedBox(height: 8),

                              // Items count and price
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${order.items.length} Pasang Sepatu',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textGray),
                                  ),
                                  Text(
                                    'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                  ),
                                ],
                              ),
                              
                              const Divider(height: 24, color: AppTheme.lightGray),

                              // Action buttons (PDF, WA Notification)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // WA Notification
                                  TextButton.icon(
                                    onPressed: () => _sendWhatsAppMessage(order),
                                    icon: const Icon(Icons.chat_bubble_outline, color: Colors.green, size: 14),
                                    label: const Text('WA Notif', style: TextStyle(color: Colors.green, fontSize: 11)),
                                  ),
                                  const SizedBox(width: 4),

                                  // Kirim PDF via native share (WhatsApp)
                                  TextButton.icon(
                                    onPressed: () => _sharePdfInvoice(order),
                                    icon: const Icon(Icons.share, color: Colors.blue, size: 14),
                                    label: const Text('Kirim PDF', style: TextStyle(color: Colors.blue, fontSize: 11)),
                                  ),
                                  const SizedBox(width: 4),

                                  // PDF Invoice Print
                                  TextButton.icon(
                                    onPressed: () => _generatePdfInvoice(order),
                                    icon: const Icon(Icons.print_outlined, color: AppTheme.textGray, size: 14),
                                    label: const Text('Cetak', style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter, String label) {
    bool isSelected = _statusFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _statusFilter = filter;
          });
        }
      },
      selectedColor: AppTheme.primaryBlue.withOpacity(0.12),
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.primaryBlue : AppTheme.textGray,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
