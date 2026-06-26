import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItem {
  final String itemName;
  final String serviceId;
  final String serviceName;
  final double price;

  OrderItem({
    required this.itemName,
    required this.serviceId,
    required this.serviceName,
    required this.price,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      itemName: map['itemName'] ?? '',
      serviceId: map['serviceId'] ?? '',
      serviceName: map['serviceName'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemName': itemName,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'price': price,
    };
  }
}

class OrderModel {
  final String id;
  final String idempotencyToken;
  final String customerName;
  final String customerPhone;
  final String customerId;
  final List<OrderItem> items;
  final double totalAmount;
  final String status; // 'diterima' | 'sedang_diproses' | 'selesai' | 'diambil'
  final String paymentStatus; // 'belum_bayar' | 'sudah_bayar'
  final String qrisImage;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrderModel({
    required this.id,
    required this.idempotencyToken,
    required this.customerName,
    required this.customerPhone,
    required this.customerId,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.paymentStatus,
    required this.qrisImage,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map, String documentId) {
    var rawItems = map['items'] as List<dynamic>? ?? [];
    List<OrderItem> parsedItems = rawItems
        .map((item) => OrderItem.fromMap(Map<String, dynamic>.from(item)))
        .toList();

    return OrderModel(
      id: documentId,
      idempotencyToken: map['idempotencyToken'] ?? '',
      customerName: map['customerName'] ?? '',
      customerPhone: map['customerPhone'] ?? '',
      customerId: map['customerId'] ?? '',
      items: parsedItems,
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'diterima',
      paymentStatus: map['paymentStatus'] ?? 'belum_bayar',
      qrisImage: map['qrisImage'] ?? '',
      notes: map['notes'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'idempotencyToken': idempotencyToken,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerId': customerId,
      'items': items.map((item) => item.toMap()).toList(),
      'totalAmount': totalAmount,
      'status': status,
      'paymentStatus': paymentStatus,
      'qrisImage': qrisImage,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
