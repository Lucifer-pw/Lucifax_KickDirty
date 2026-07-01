import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/order_model.dart';
import '../../theme.dart';

class ReviewModerationScreen extends StatefulWidget {
  const ReviewModerationScreen({Key? key}) : super(key: key);

  @override
  State<ReviewModerationScreen> createState() => _ReviewModerationScreenState();
}

class _ReviewModerationScreenState extends State<ReviewModerationScreen> {
  late Stream<List<OrderModel>> _reviewsStream;

  @override
  void initState() {
    super.initState();
    _reviewsStream = FirebaseFirestore.instance
        .collection('orders')
        .where('rating', isNull: false)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .toList();
      // Sort in-memory by reviewedAt descending to avoid requiring composite indexes
      list.sort((a, b) {
        final dateA = a.reviewedAt ?? a.createdAt;
        final dateB = b.reviewedAt ?? b.createdAt;
        return dateB.compareTo(dateA);
      });
      return list;
    });
  }

  Widget _buildBase64Image(String base64Str, String label, {double height = 90}) {
    if (base64Str.isEmpty) {
      return Container(
        height: height,
        width: height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 24, color: Colors.grey),
        ),
      );
    }
    try {
      String cleanBase64 = base64Str.trim();
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',')[1];
      }
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(cleanBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          height: height,
          width: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: height,
            width: height,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
          ),
        ),
      );
    } catch (_) {
      return Container(
        height: height,
        width: height,
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderasi Ulasan Web'),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.darkBlueText,
        elevation: 0.5,
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: _reviewsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Terjadi kesalahan: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textGray),
                ),
              ),
            );
          }

          final reviews = snapshot.data ?? [];
          if (reviews.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rate_review_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    'Belum ada ulasan masuk dari pelanggan.',
                    style: TextStyle(color: AppTheme.textGray, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index];
              final date = review.reviewedAt ?? review.createdAt;
              final formattedDate = "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Customer Info & Rating
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  review.customerName.isEmpty ? 'Pelanggan Anonim' : review.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  review.customerPhone,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Order: ${review.id}',
                                  style: const TextStyle(fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          // Rating Stars
                          Row(
                            children: List.generate(5, (indexStar) {
                              return Icon(
                                indexStar < (review.rating ?? 5.0) ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 16,
                              );
                            }),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      // Layanan Info
                      Text(
                        review.items.map((e) {
                          final parts = <String>[];
                          parts.add('Nama barang= ${e.itemName}');
                          if (e.categoryName.isNotEmpty) {
                            parts.add('kategori = (${e.categoryName})');
                          }
                          if (e.serviceName.isNotEmpty) {
                            parts.add('layanan (${e.serviceName})');
                          }
                          return parts.join(', ');
                        }).join('; '),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                      ),
                      const SizedBox(height: 8),

                      // Review Text
                      if (review.reviewText != null && review.reviewText!.isNotEmpty) ...[
                        Text(
                          '"${review.reviewText}"',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.darkBlueText),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Before-After Preview (If available)
                      if (review.photoBefore.isNotEmpty || review.photoAfter.isNotEmpty) ...[
                        Row(
                          children: [
                            if (review.photoBefore.isNotEmpty) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Before', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textGray)),
                                  const SizedBox(height: 4),
                                  _buildBase64Image(review.photoBefore.first, 'Before', height: 80),
                                ],
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (review.photoAfter.isNotEmpty) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('After', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textGray)),
                                  const SizedBox(height: 4),
                                  _buildBase64Image(review.photoAfter.first, 'After', height: 80),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Footer & Moderation Action
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(fontSize: 10, color: AppTheme.textGray),
                          ),
                          Row(
                            children: [
                              Text(
                                review.showOnWeb ? 'Ditampilkan di Web' : 'Disembunyikan',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: review.showOnWeb ? Colors.green : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: review.showOnWeb,
                                activeColor: Colors.green,
                                onChanged: (val) async {
                                  await FirebaseFirestore.instance
                                      .collection('orders')
                                      .doc(review.id)
                                      .update({'showOnWeb': val});
                                },
                              ),
                            ],
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
    );
  }
}
