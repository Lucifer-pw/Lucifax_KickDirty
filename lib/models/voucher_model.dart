import 'package:cloud_firestore/cloud_firestore.dart';

class VoucherModel {
  final String id;
  final String code;
  final String name;
  final String description;
  final String discountType; // 'percentage' | 'fixed'
  final double discountValue;
  final double minOrder;
  final double maxDiscount;
  final bool isActive;
  final DateTime? validFrom;
  final DateTime? validTo;
  final DateTime createdAt;

  VoucherModel({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    this.discountType = 'fixed',
    required this.discountValue,
    this.minOrder = 0.0,
    this.maxDiscount = 0.0,
    this.isActive = true,
    this.validFrom,
    this.validTo,
    required this.createdAt,
  });

  factory VoucherModel.fromMap(Map<String, dynamic> map, String documentId) {
    return VoucherModel(
      id: documentId,
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      discountType: map['discountType'] ?? 'fixed',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0.0,
      minOrder: (map['minOrder'] as num?)?.toDouble() ?? 0.0,
      maxDiscount: (map['maxDiscount'] as num?)?.toDouble() ?? 0.0,
      isActive: map['isActive'] ?? true,
      validFrom: (map['validFrom'] as Timestamp?)?.toDate(),
      validTo: (map['validTo'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'description': description,
      'discountType': discountType,
      'discountValue': discountValue,
      'minOrder': minOrder,
      'maxDiscount': maxDiscount,
      'isActive': isActive,
      'validFrom': validFrom != null ? Timestamp.fromDate(validFrom!) : null,
      'validTo': validTo != null ? Timestamp.fromDate(validTo!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Calculate actual discount for a given order total
  double calculateDiscount(double orderTotal) {
    if (!isActive) return 0.0;
    if (orderTotal < minOrder) return 0.0;

    final now = DateTime.now();
    if (validFrom != null && now.isBefore(validFrom!)) return 0.0;
    if (validTo != null && now.isAfter(validTo!)) return 0.0;

    if (discountType == 'percentage') {
      double discount = orderTotal * (discountValue / 100);
      if (maxDiscount > 0 && discount > maxDiscount) {
        discount = maxDiscount;
      }
      return discount;
    } else {
      return discountValue;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoucherModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
