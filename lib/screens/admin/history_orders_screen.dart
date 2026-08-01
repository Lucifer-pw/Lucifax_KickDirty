import 'dart:async';
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
import '../../services/local_cache_service.dart';
import '../../theme.dart';
import '../../widgets/invoice_detail_modal.dart';
import '../../widgets/pagination_bar_widget.dart';
import '../../utils/error_helper.dart';
import '../../utils/printer/printer_service.dart';

class HistoryOrdersScreen extends StatefulWidget {
  final bool isTab;
  const HistoryOrdersScreen({Key? key, this.isTab = false}) : super(key: key);

  @override
  State<HistoryOrdersScreen> createState() => _HistoryOrdersScreenState();
}

class _HistoryOrdersScreenState extends State<HistoryOrdersScreen> {
  String _searchQuery = '';
  String _statusFilter = 'semua'; // 'semua' | 'diterima' | 'sedang_diproses' | 'selesai' | 'diambil'

  // --- Numbered Pagination State ---
  int _itemsPerPage = 25;
  int _currentPage = 1;
  int _totalCount = 0;
  bool _isLoadingCount = true;
  bool _isLoadingPage = true;

  final Map<int, List<OrderModel>> _pageOrdersCache = {};
  final Map<int, DocumentSnapshot?> _pageLastDocs = {};
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPagination();
    });
  }

  void _cancelSubscriptions() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _initPagination() async {
    _cancelSubscriptions();
    setState(() {
      _isLoadingCount = true;
      _isLoadingPage = true;
      _pageOrdersCache.clear();
      _pageLastDocs.clear();
      _currentPage = 1;
    });

    final dbService = Provider.of<DatabaseService>(context, listen: false);
    
    // 1. Fetch total count (using cheap count query)
    final count = await dbService.getOrdersHistoryCount(statusFilter: _statusFilter);
    if (!mounted) return;

    setState(() {
      _totalCount = count;
      _isLoadingCount = false;
    });

    // 2. Fetch page 1
    _fetchPage(1);
  }

  Future<void> _fetchPage(int page) async {
    // 1. Instant 0ms render from Memory Cache or Persistent Disk Cache (/cache/)
    if (_pageOrdersCache.containsKey(page)) {
      setState(() {
        _currentPage = page;
        _isLoadingPage = false;
        _isLoadingCount = false;
      });
    } else {
      final cachedData = await LocalCacheService.instance.getHistoryPageCache(
        page: page,
        itemsPerPage: _itemsPerPage,
        statusFilter: _statusFilter,
      );
      if (cachedData != null && mounted) {
        final List<OrderModel> cachedOrders = cachedData['orders'];
        final int cachedTotal = cachedData['totalCount'];
        setState(() {
          _currentPage = page;
          _pageOrdersCache[page] = cachedOrders;
          if (cachedTotal > 0) _totalCount = cachedTotal;
          _isLoadingPage = false;
          _isLoadingCount = false;
        });
      } else {
        setState(() {
          _currentPage = page;
          _isLoadingPage = true;
        });
      }
    }

    // 2. Real-time background stream listener from Firestore
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final DocumentSnapshot? startAfterDoc = page > 1 ? _pageLastDocs[page - 1] : null;

    final sub = dbService.getPaginatedOrdersSnapshot(
      limit: _itemsPerPage,
      startAfterDoc: startAfterDoc,
      statusFilter: _statusFilter,
    ).listen((snapshot) {
      if (!mounted) return;

      final orders = snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();

      setState(() {
        _pageOrdersCache[page] = orders;
        if (snapshot.docs.isNotEmpty) {
          _pageLastDocs[page] = snapshot.docs.last;
        }
        _isLoadingPage = false;
        _isLoadingCount = false;
      });

      // Save fresh data to local persistent cache
      LocalCacheService.instance.saveHistoryPageCache(
        page: page,
        itemsPerPage: _itemsPerPage,
        statusFilter: _statusFilter,
        orders: orders,
        totalCount: _totalCount,
      );
    });

    _subscriptions.add(sub);
  }

  void _onItemsPerPageChanged(int newLimit) {
    setState(() {
      _itemsPerPage = newLimit;
    });
    _initPagination();
  }

  void _onPageChanged(int newPage) {
    _fetchPage(newPage);
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
  // --- End Pagination State ---

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
                      if (order.voucherCode.isNotEmpty)
                        pw.Text(
                          'Voucher: ${order.voucherCode}${order.voucherName.isNotEmpty ? " (${order.voucherName})" : ""}${order.voucherDiscount > 0 ? " (-Rp ${order.voucherDiscount.toStringAsFixed(0)})" : ""}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.green),
                        ),
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
  Future<void> _generatePdfInvoice(OrderModel order, {bool isThermal = false}) async {
    String shopName = "KickDirty";
    String shopPhone = "6281328580511";
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (doc.exists) {
        shopName = doc.data()?['shopName'] ?? "KickDirty";
        shopPhone = doc.data()?['shopPhone'] ?? "6281328580511";
      }
    } catch (_) {}

    final pdf = isThermal 
        ? _buildThermalInvoiceDocument(order, shopName, shopPhone)
        : _buildPdfInvoiceDocument(order, shopName, shopPhone);

    // Direct bluetooth printing check if thermal is chosen
    if (isThermal) {
      final isPrinterConnected = await PrinterService.instance.isConnected();
      if (isPrinterConnected) {
        // Show printing overlay/loader
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
                    Text('Mencetak langsung ke printer...', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );

        try {
          final pdfBytes = await pdf.save();
          await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 180)) {
            final pngBytes = await page.toPng();
            await PrinterService.instance.printThermal(pngBytes);
          }
          if (mounted) {
            Navigator.pop(context); // close loader
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Struk berhasil dicetak!'), backgroundColor: Colors.green),
            );
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context); // close loader
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal mencetak: $e'), backgroundColor: Colors.red),
            );
          }
        }
        return; // Exit, do not open standard print dialog
      }
    }

    // Fallback or Standard: Open print preview
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: isThermal ? 'thermal_${order.id}.pdf' : 'invoice_${order.id}.pdf',
      format: isThermal 
          ? const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm)
          : PdfPageFormat.a5,
    );
  }

  // Build 58mm Thermal Printer Invoice Document
  pw.Document _buildThermalInvoiceDocument(OrderModel order, String shopName, String shopPhone) {
    final pdf = pw.Document();

    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      shopName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Laundry Sepatu',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.Text(
                      'HP/WA: $shopPhone',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('-' * 28, style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),

              // Metadata
              pw.Text('No: ${order.id}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('Tgl: $formattedDate', style: const pw.TextStyle(fontSize: 7)),
              pw.Text('Cust: ${order.customerName}', style: const pw.TextStyle(fontSize: 7)),
              pw.Text('Status: ${order.status.toUpperCase()}', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 4),
              pw.Text('-' * 28, style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),

              // Items List
              ...order.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(item.itemName, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(' (${item.serviceName})', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
                          pw.Text('Rp ${item.price.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 7)),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              pw.Text('-' * 28, style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),

              // Pricing details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text('Rp ${order.items.fold(0.0, (sum, item) => sum + item.price).toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              if (order.deliveryFee > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Ongkir:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text('Rp ${order.deliveryFee.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              if (order.voucherCode.isNotEmpty) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Voucher:', style: const pw.TextStyle(fontSize: 7, color: PdfColors.green)),
                    pw.Text(
                      '${order.voucherCode}${order.voucherName.isNotEmpty ? " (${order.voucherName})" : ""}',
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.green),
                    ),
                  ],
                ),
                if (order.voucherDiscount > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('  Diskon Vch:', style: const pw.TextStyle(fontSize: 7, color: PdfColors.green)),
                      pw.Text('-Rp ${order.voucherDiscount.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.green)),
                    ],
                  ),
              ],
              if (order.pointsRedeemed > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Poin Red:', style: const pw.TextStyle(fontSize: 7, color: PdfColors.green)),
                    pw.Text(
                      '-Rp ${((order.items.fold(0.0, (sum, item) => sum + item.price) + order.deliveryFee - order.voucherDiscount) - order.totalAmount).clamp(0.0, double.infinity).toStringAsFixed(0)}',
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.green),
                    ),
                  ],
                ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rp ${order.totalAmount.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),

              if (order.notes.isNotEmpty) ...[
                pw.Text('Notes: ${order.notes}', style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 4),
              ],

              pw.Text('-' * 28, style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 6),

              // Footer
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Terima kasih!', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Sepatu bersih, langkah percaya diri.', style: const pw.TextStyle(fontSize: 6)),
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

  // Show print options selection dialog
  void _showPrintOptionsDialog(OrderModel order) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.white,
          title: Text(
            'Pilih Format Cetak',
            style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primaryBlue),
                title: Text('Format A5 (Standar PDF)', style: TextStyle(color: AppTheme.darkBlueText)),
                subtitle: Text('Sesuai untuk printer inkjet/laser A4/A5', style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  _generatePdfInvoice(order, isThermal: false);
                },
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.print_outlined, color: Colors.green),
                title: Text('Format Thermal (58mm)', style: TextStyle(color: AppTheme.darkBlueText)),
                subtitle: Text('Sesuai untuk printer bluetooth kasir roll', style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  _generatePdfInvoice(order, isThermal: true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Batal', style: TextStyle(color: AppTheme.textGray)),
            ),
          ],
        );
      },
    );
  }

  // Share PDF invoice to WA or other apps
  Future<void> _sharePdfInvoice(OrderModel order) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
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
              SnackBar(content: Text('Invoice PDF berhasil dikirim otomatis ke WhatsApp pelanggan sebagai berkas dokumen asli!')),
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

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  @override
  Widget build(BuildContext context) {
    // dbService removed from build as it's now used in initState/loadMore

    return Scaffold(
      appBar: AppBar(
        title: Text('Riwayat Transaksi'),
        automaticallyImplyLeading: !widget.isTab,
      ),
      body: Column(
        children: [
          // Filter & Search Header
          Padding(
            padding: EdgeInsets.all(16.0),
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
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: AppTheme.lightBlueBackground.withOpacity(0.5),
                  ),
                ),
                SizedBox(height: 12),
                
                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('semua', 'Semua'),
                      SizedBox(width: 8),
                      _buildFilterChip('diterima', 'Diterima'),
                      SizedBox(width: 8),
                      _buildFilterChip('sedang_diproses', 'Diproses'),
                      SizedBox(width: 8),
                      _buildFilterChip('selesai', 'Selesai'),
                      SizedBox(width: 8),
                      _buildFilterChip('diambil', 'Diambil'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Orders List
          Expanded(
            child: (_isLoadingCount || _isLoadingPage)
                ? Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      var orders = _pageOrdersCache[_currentPage] ?? [];

                      // Filter by Search Query
                      if (_searchQuery.isNotEmpty) {
                        orders = orders.where((o) {
                          return o.customerName.toLowerCase().contains(_searchQuery) ||
                              o.customerPhone.contains(_searchQuery) ||
                              o.id.toLowerCase().contains(_searchQuery);
                        }).toList();
                      }

                      if (orders.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off, size: 64, color: AppTheme.textGray),
                              SizedBox(height: 16),
                              Text(
                                'Tidak ada riwayat pesanan',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textGray),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final order = orders[index];

                          // Date formatting: DD-MM-YYYY
                          String day = order.createdAt.day.toString().padLeft(2, '0');
                          String month = order.createdAt.month.toString().padLeft(2, '0');
                          String year = order.createdAt.year.toString();
                          String formattedDate = "$day-$month-$year";

                          // Determine Status Color & Display Text
                          Color statusColor = Colors.grey;
                          String statusText = order.status.toUpperCase();
                          if (order.status == 'diterima' || order.status == 'dibayar') {
                            statusColor = Colors.orange;
                          } else if (order.status == 'sedang_diproses' || order.status == 'diproses') {
                            statusColor = AppTheme.primaryBlue;
                          } else if (order.status == 'selesai') {
                            statusColor = Colors.teal;
                          } else if (order.status == 'diambil') {
                            statusColor = Colors.green;
                          }

                          // Build item summary description
                          String itemDesc = '';
                          if (order.items.isNotEmpty) {
                            final names = order.items
                                .map((e) => e.itemName.isNotEmpty ? e.itemName : e.serviceName)
                                .where((n) => n.isNotEmpty)
                                .join(', ');
                            if (names.isNotEmpty) {
                              itemDesc = '${order.items.length} Pasang $names';
                            } else {
                              itemDesc = '${order.items.length} Pasang Sepatu';
                            }
                          } else {
                            itemDesc = '1 Pasang Sepatu';
                          }

                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: AppTheme.lightGray, width: 1),
                            ),
                            child: InkWell(
                              onTap: () => InvoiceDetailModal.show(context, order),
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top Header: Invoice ID (Left) & Status Badge (Right)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          order.id,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor.withOpacity(0.3)),
                                          ),
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    SizedBox(height: 10),
                                    Divider(height: 1, color: AppTheme.lightGray),
                                    SizedBox(height: 10),

                                    // Customer Name & Date
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText),
                                        children: [
                                          TextSpan(
                                            text: 'Pelanggan: ',
                                            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textGray),
                                          ),
                                          TextSpan(
                                            text: order.customerName,
                                            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(fontSize: 12, color: AppTheme.textGray),
                                        children: [
                                          TextSpan(text: 'Tanggal: '),
                                          TextSpan(text: formattedDate, style: TextStyle(color: AppTheme.darkBlueText.withOpacity(0.8))),
                                        ],
                                      ),
                                    ),

                                    SizedBox(height: 10),

                                    // Item summary (Left) & Total Amount (Right)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            itemDesc,
                                            style: TextStyle(fontSize: 12, color: AppTheme.textGray),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Rp ${_formatCurrency(order.totalAmount)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: AppTheme.darkBlueText,
                                          ),
                                        ),
                                      ],
                                    ),

                                    SizedBox(height: 10),
                                    Divider(height: 1, color: AppTheme.lightGray),
                                    SizedBox(height: 4),

                                    // Action buttons (WA Notif, Kirim PDF, Cetak)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // WA Notification
                                        TextButton.icon(
                                          onPressed: () => _sendWhatsAppMessage(order),
                                          icon: Icon(Icons.chat_bubble_outline, color: Colors.green, size: 14),
                                          label: Text('WA Notif', style: TextStyle(color: Colors.green, fontSize: 11)),
                                        ),
                                        SizedBox(width: 4),

                                        // Kirim PDF via native share (WhatsApp)
                                        TextButton.icon(
                                          onPressed: () => _sharePdfInvoice(order),
                                          icon: Icon(Icons.share, color: Colors.blue, size: 14),
                                          label: Text('Kirim PDF', style: TextStyle(color: Colors.blue, fontSize: 11)),
                                        ),
                                        SizedBox(width: 4),

                                        // PDF Invoice Print
                                        TextButton.icon(
                                          onPressed: () => _showPrintOptionsDialog(order),
                                          icon: Icon(Icons.print_outlined, color: AppTheme.textGray, size: 14),
                                          label: Text('Cetak', style: TextStyle(color: AppTheme.textGray, fontSize: 11)),
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
          // Numbered Pagination Bar at the bottom
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: PaginationBarWidget(
              totalItems: _totalCount,
              currentPage: _currentPage,
              itemsPerPage: _itemsPerPage,
              onPageChanged: _onPageChanged,
              onItemsPerPageChanged: _onItemsPerPageChanged,
              itemUnitName: 'transaksi',
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
        if (val && _statusFilter != filter) {
          setState(() {
            _statusFilter = filter;
          });
          _initPagination();
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
