import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceModel {
  final String id;
  final String name;
  final double price;
  final String description;
  final DateTime createdAt;

  ServiceModel({
    required this.id,
    required this.name,
    required this.price,
    required this.description,
    required this.createdAt,
  });

  factory ServiceModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ServiceModel(
      id: documentId,
      name: map['name'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      description: map['description'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServiceModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
