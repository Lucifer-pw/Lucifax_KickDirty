import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_model.dart';
import '../theme.dart';

class InvoiceDetailModal extends StatelessWidget {
  final OrderModel order;
  const InvoiceDetailModal({Key? key, required this.order}) : super(key: key);

  static void show(BuildContext context, OrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => InvoiceDetailModal(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy HH:mm');
    
    // Status colors
    Color statusColor = Colors.grey;
    if (order.status == 'diterima') statusColor = Colors.orange;
    if (order.status == 'sedang_diproses') statusColor = AppTheme.primaryBlue;
    if (order.status == 'selesai') statusColor = Colors.teal;
    if (order.status == 'diambil') statusColor = Colors.green;

    // Delivery type text
    String deliveryText = order.deliveryType == 'pickup_delivery' 
        ? 'Penjemputan & Pengantaran (Kurir)'
        : 'Drop-Off & Ambil Sendiri';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.lightGray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detail Invoice',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textGray),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const Divider(height: 16, color: AppTheme.lightGray),
          
          // Scrollable body
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Invoice ID & Status Badges
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order.id,
                        style: const TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold, 
                          color: AppTheme.darkBlueText
                        ),
                      ),
                      Row(
                        children: [
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
                                fontSize: 9,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: order.paymentStatus == 'sudah_bayar'
                                  ? Colors.green.withOpacity(0.12)
                                  : Colors.red.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.paymentStatus == 'sudah_bayar' ? 'LUNAS' : 'BELUM BAYAR',
                              style: TextStyle(
                                color: order.paymentStatus == 'sudah_bayar' ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Metadata
                  _buildInfoRow('Pelanggan:', order.customerName),
                  _buildInfoRow('No. WhatsApp:', order.customerPhone),
                  _buildInfoRow('Tanggal Masuk:', dateFormat.format(order.createdAt)),
                  if (order.estimatedCompletion.isNotEmpty)
                    _buildInfoRow('Estimasi Selesai:', order.estimatedCompletion, valueColor: Colors.orange),
                  
                  const SizedBox(height: 16),
                  const Text('Daftar Layanan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText)),
                  const SizedBox(height: 6),
                  
                  // Items Table
                  ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              Text(item.serviceName, style: const TextStyle(color: AppTheme.textGray, fontSize: 10)),
                            ],
                          ),
                        ),
                        Text(
                          'Rp ${item.price.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  )),
                  
                  const Divider(height: 20, color: AppTheme.lightGray),
                  
                  // Logistics / Delivery details
                  const Text('Rincian Logistik & Pengiriman', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText)),
                  const SizedBox(height: 6),
                  _buildInfoRow('Metode Logistik:', deliveryText),
                  if (order.deliveryType == 'pickup_delivery') ...[
                    _buildInfoRow('Ongkos Kirim:', 'Rp ${order.deliveryFee.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}'),
                    _buildInfoRow('Alamat Pengiriman:', order.deliveryAddress),
                  ],
                  
                  const Divider(height: 20, color: AppTheme.lightGray),
                  
                  // Timeline Status Updates
                  const Text('Linimasa Pembaruan Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText)),
                  const SizedBox(height: 8),
                  _buildTimelineItem('Diterima', order.statusTimeline['diterima'], dateFormat),
                  _buildTimelineItem('Sedang Diproses', order.statusTimeline['sedang_diproses'], dateFormat),
                  _buildTimelineItem('Selesai Di-servis', order.statusTimeline['selesai'], dateFormat),
                  _buildTimelineItem('Dibayar / Lunas', order.statusTimeline['sudah_bayar'], dateFormat),
                  _buildTimelineItem('Diserahkan ke Pelanggan', order.statusTimeline['diambil'], dateFormat),
                  
                  const Divider(height: 20, color: AppTheme.lightGray),

                  // Pricing Summary
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Pembayaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText)),
                      Text(
                        'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                      ),
                    ],
                  ),
                  if (order.pointsRedeemed > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Poin Ditukar:', style: TextStyle(color: Colors.green, fontSize: 11)),
                        Text('${order.pointsRedeemed} Poin (Diskon Rp 25.000)', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                  if (order.pointsEarned > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Poin Didapatkan:', style: TextStyle(color: Colors.orange, fontSize: 11)),
                        Text('+${order.pointsEarned} Poin', style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                  
                  if (order.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Catatan: "${order.notes}"',
                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.orange, fontSize: 11),
                    ),
                  ],

                  // Photos before-after
                  if (order.photoBefore.isNotEmpty || order.photoAfter.isNotEmpty) ...[
                    const Divider(height: 24, color: AppTheme.lightGray),
                    const Text('Dokumentasi Foto Cucian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (order.photoBefore.isNotEmpty)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: _buildImageThumbnail(context, order.photoBefore.first, 'Kondisi Awal (Before)'),
                            ),
                          ),
                        if (order.photoAfter.isNotEmpty)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6.0),
                              child: _buildImageThumbnail(context, order.photoAfter.first, 'Hasil Cuci (After)'),
                            ),
                          )
                        else if (order.photoBefore.isNotEmpty)
                          const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: AppTheme.textGray, fontSize: 11)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11, 
                fontWeight: FontWeight.w600, 
                color: valueColor ?? AppTheme.darkBlueText
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(String label, DateTime? timestamp, DateFormat format) {
    final bool isDone = timestamp != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isDone ? Colors.green : AppTheme.textGray.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                color: isDone ? AppTheme.darkBlueText : AppTheme.textGray,
              ),
            ),
          ),
          if (isDone)
            Text(
              format.format(timestamp),
              style: const TextStyle(fontSize: 10, color: AppTheme.textGray),
            )
          else
            const Text(
              'Belum',
              style: TextStyle(fontSize: 10, color: AppTheme.textGray, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, String base64Str, String label) {
    try {
      String cleanBase64 = base64Str;
      if (base64Str.contains(',')) {
        cleanBase64 = base64Str.split(',')[1];
      }
      final bytes = base64Decode(cleanBase64);
      return GestureDetector(
        onTap: () {
          // Open fullscreen zoom
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(12),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withOpacity(0.6),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                image: DecorationImage(
                  image: MemoryImage(bytes),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textGray, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    } catch (e) {
      return Container(
        height: 100,
        color: AppTheme.lightGray,
        child: const Center(child: Icon(Icons.broken_image, color: AppTheme.textGray)),
      );
    }
  }
}
