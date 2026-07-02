import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../utils/platform_helper.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  UserModel? _currentUserModel;

  UserModel? get currentUserModel => _currentUserModel;
  User? get currentUser => _auth.currentUser;

  AuthService() {
    // Listen to authentication changes
    _auth.userChanges().listen((User? user) async {
      if (user != null) {
        await _fetchUserModel(user.uid);
      } else {
        _currentUserModel = null;
      }
      notifyListeners();
    });
  }

  // Normalize phone number: convert 08xx or +62xx to 628xx format
  static String normalizePhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '62${cleaned.substring(1)}';
    }
    return cleaned;
  }

  // Fetch user model from Firestore
  Future<void> _fetchUserModel(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        _currentUserModel = UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        if (_currentUserModel!.phoneNumber.isNotEmpty) {
          final normalized = normalizePhone(_currentUserModel!.phoneNumber);
          _db.collection('phone_lookups').doc(normalized).set({
            'email': _currentUserModel!.email,
            'uid': uid,
          }).catchError((_) {});
        }
      } else {
        // If user document does not exist, create it as a customer (e.g. Google Sign-In new user)
        if (_auth.currentUser != null) {
          _currentUserModel = UserModel(
            uid: uid,
            name: _auth.currentUser!.displayName ?? 'Customer',
            email: _auth.currentUser!.email ?? '',
            phoneNumber: '',
            role: 'customer',
            createdAt: DateTime.now(),
          );
          await _db.collection('users').doc(uid).set(_currentUserModel!.toMap());
        }
      }
      
      // Log the login details to Firestore
      if (_currentUserModel != null) {
        _logLogin(uid).catchError((_) {});
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching user model: $e");
    }
  }

  // Record login device and location log
  Future<void> _logLogin(String uid) async {
    try {
      final device = getDevice();
      String location = 'Unknown';
      String ip = '';
      try {
        final response = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          ip = data['ip'] ?? '';
          final city = data['city'] ?? '';
          final region = data['region'] ?? '';
          final country = data['country_name'] ?? '';
          if (city.isNotEmpty || region.isNotEmpty || country.isNotEmpty) {
            location = '$city, $region, $country';
          }
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching IP location: $e");
      }

      await _db.collection('login_logs').add({
        'userId': uid,
        'userName': _currentUserModel?.name ?? 'Anonim',
        'userEmail': _currentUserModel?.email ?? '',
        'userRole': _currentUserModel?.role ?? '',
        'loginAt': FieldValue.serverTimestamp(),
        'device': device,
        'location': location,
        'ipAddress': ip,
      });
    } catch (e) {
      if (kDebugMode) print("Error logging login details: $e");
    }
  }

  // Sign In
  Future<UserCredential?> signIn(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _fetchUserModel(userCredential.user!.uid);
      notifyListeners();
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  // Sign In with Phone/WhatsApp (lookup email from phone, then authenticate)
  Future<UserCredential?> signInWithPhone(String phoneNumber, String password) async {
    try {
      final normalized = normalizePhone(phoneNumber);
      final lookupDoc = await _db
          .collection('phone_lookups')
          .doc(normalized)
          .get();

      if (!lookupDoc.exists) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Nomor WhatsApp tidak terdaftar. Silakan daftar akun baru.',
        );
      }

      final email = lookupDoc.get('email') as String;
      return await signIn(email, password);
    } catch (e) {
      rethrow;
    }
  }

  // Sign In with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null; // Cancelled by user

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      await _fetchUserModel(userCredential.user!.uid);
      notifyListeners();
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  // Register (Customer or other roles)
  Future<UserCredential?> register({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
    required String role, // 'owner' | 'staff' | 'customer'
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final normalized = normalizePhone(phoneNumber);

      // Check if there is an existing record in customers collection with ID matching normalized
      int existingPoints = 0;
      try {
        DocumentSnapshot customerDoc = await _db.collection('customers').doc(normalized).get();
        if (customerDoc.exists) {
          final data = customerDoc.data() as Map<String, dynamic>? ?? {};
          existingPoints = data['loyaltyPoints'] as int? ?? 0;

          // Update the customers document with user's UID and user's registered name
          await _db.collection('customers').doc(normalized).update({
            'uid': userCredential.user!.uid,
            'name': name.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // If no record exists, create one in the customers collection
          await _db.collection('customers').doc(normalized).set({
            'name': name.trim(),
            'phone': normalized,
            'uid': userCredential.user!.uid,
            'loyaltyPoints': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        if (kDebugMode) print("Error linking customer record on register: $e");
      }

      _currentUserModel = UserModel(
        uid: userCredential.user!.uid,
        name: name.trim(),
        email: email.trim(),
        phoneNumber: normalized,
        role: role,
        loyaltyPoints: existingPoints,
        createdAt: DateTime.now(),
      );

      await _db.collection('users').doc(userCredential.user!.uid).set(_currentUserModel!.toMap());
      
      await _db.collection('phone_lookups').doc(normalized).set({
        'email': email.trim(),
        'uid': userCredential.user!.uid,
      }).catchError((_) {});

      notifyListeners();
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
    _currentUserModel = null;
    notifyListeners();
  }
}
