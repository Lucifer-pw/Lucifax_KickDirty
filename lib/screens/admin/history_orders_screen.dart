import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';

class HistoryOrdersScreen extends StatefulWidget {
  final bool isTab;
  const HistoryOrdersScreen({Key? key, this.isTab = false}) : super(key: key);

  @override
  State<HistoryOrdersScreen> createState() => _HistoryOrdersScreenState();
}

class _HistoryOrdersScreenState extends State<HistoryOrdersScreen> {
  String _searchQuery = '';
  String _statusFilter = 'semua'; // 'semua' | 'diterima' | 'sedang_diproses' | 'selesai' | 'diambil'

  // Generate and print PDF invoice
  Future<void> _generatePdfInvoice(OrderModel order) async {
    final pdf = pw.Document();

    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // Receipt roll size, highly practical for shops
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'KICK DIRTY',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Shoe Cleaning & Care Services',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      'HP/WA: 6281328580511',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      '--------------------------------------',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 5),

              // Invoice Metadata
              pw.Text('Invoice: ${order.id}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Tanggal: $formattedDate', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Customer: ${order.customerName}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Status: ${order.status.toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                '--------------------------------------',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),

              // Items Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Layanan / Sepatu', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Harga', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 3),

              // Items List
              ...order.items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(item.itemName, style: const pw.TextStyle(fontSize: 8)),
                              pw.Text('(${item.serviceName})', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
                            ],
                          ),
                        ),
                        pw.Text(
                          'Rp ${item.price.toStringAsFixed(0)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  )),

              pw.Text(
                '--------------------------------------',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),

              // Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    'Rp ${order.totalAmount.toStringAsFixed(0)}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),

              // Payment Status
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Pembayaran:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                    order.paymentStatus == 'sudah_bayar' ? 'LUNAS' : 'BELUM BAYAR',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              
              if (order.notes.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text('Catatan: ${order.notes}', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
              ],

              pw.SizedBox(height: 15),
              // Footer
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Terima kasih atas kunjungan Anda!', style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 2),
                    pw.Text('Powered by Lucifax', style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // Open print preview
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'invoice_${order.id}.pdf',
    );
  }

  Future<void> _sendWhatsAppMessage(OrderModel order) async {
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
        'Powered by KickDirty';

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
                                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.green, size: 16),
                                  label: const Text('WA Notif', style: TextStyle(color: Colors.green, fontSize: 12)),
                                ),
                                const SizedBox(width: 8),

                                // PDF Invoice Print
                                TextButton.icon(
                                  onPressed: () => _generatePdfInvoice(order),
                                  icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primaryBlue, size: 16),
                                  label: const Text('Cetak PDF', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
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
