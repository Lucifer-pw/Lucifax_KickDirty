import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final String role; // 'owner' | 'staff' | 'customer'
  final int loyaltyPoints;
  final String addressDetail;
  final String mapsLink;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.role,
    this.loyaltyPoints = 0,
    this.addressDetail = '',
    this.mapsLink = '',
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return UserModel(
      uid: documentId,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      role: map['role'] ?? 'customer',
      loyaltyPoints: map['loyaltyPoints'] ?? 0,
      addressDetail: map['addressDetail'] ?? '',
      mapsLink: map['mapsLink'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'role': role,
      'loyaltyPoints': loyaltyPoints,
      'addressDetail': addressDetail,
      'mapsLink': mapsLink,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
