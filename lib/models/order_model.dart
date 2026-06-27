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
  final String deliveryType; // 'drop_off_only' | 'pickup_delivery'
  final String deliveryAddress;
  final double deliveryFee;
  final List<String> photoBefore;
  final List<String> photoAfter;
  final int pointsEarned;
  final int pointsRedeemed;
  final String estimatedCompletion;
  final String mapsLink;
  final Map<String, DateTime> statusTimeline;
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
    this.deliveryType = 'drop_off_only',
    this.deliveryAddress = '',
    this.deliveryFee = 0.0,
    this.photoBefore = const [],
    this.photoAfter = const [],
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
    this.estimatedCompletion = '',
    this.mapsLink = '',
    this.statusTimeline = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map, String documentId) {
    var rawItems = map['items'] as List<dynamic>? ?? [];
    List<OrderItem> parsedItems = rawItems
        .map((item) => OrderItem.fromMap(Map<String, dynamic>.from(item)))
        .toList();

    Map<String, dynamic> rawTimeline = map['statusTimeline'] as Map<String, dynamic>? ?? {};
    Map<String, DateTime> timeline = {};
    rawTimeline.forEach((key, value) {
      if (value is Timestamp) {
        timeline[key] = value.toDate();
      } else if (value is String) {
        timeline[key] = DateTime.parse(value);
      }
    });

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
      deliveryType: map['deliveryType'] ?? 'drop_off_only',
      deliveryAddress: map['deliveryAddress'] ?? '',
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble() ?? 0.0,
      photoBefore: List<String>.from(map['photoBefore'] ?? []),
      photoAfter: List<String>.from(map['photoAfter'] ?? []),
      pointsEarned: map['pointsEarned'] ?? 0,
      pointsRedeemed: map['pointsRedeemed'] ?? 0,
      estimatedCompletion: map['estimatedCompletion'] ?? '',
      mapsLink: map['mapsLink'] ?? '',
      statusTimeline: timeline,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    Map<String, Timestamp> timelineDb = {};
    statusTimeline.forEach((key, value) {
      timelineDb[key] = Timestamp.fromDate(value);
    });

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
      'deliveryType': deliveryType,
      'deliveryAddress': deliveryAddress,
      'deliveryFee': deliveryFee,
      'photoBefore': photoBefore,
      'photoAfter': photoAfter,
      'pointsEarned': pointsEarned,
      'pointsRedeemed': pointsRedeemed,
      'estimatedCompletion': estimatedCompletion,
      'mapsLink': mapsLink,
      'statusTimeline': timelineDb,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
