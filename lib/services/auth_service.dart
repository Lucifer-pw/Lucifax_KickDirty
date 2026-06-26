import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class AuthService with ChangeNotifier {
  FirebaseAuth? get _auth => Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null;
  FirebaseFirestore? get _db => Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null;

  UserModel? _currentUserModel;
  UserModel? _mockUser;

  UserModel? get currentUserModel => Firebase.apps.isNotEmpty ? _currentUserModel : _mockUser;
  User? get currentUser => Firebase.apps.isNotEmpty ? _auth?.currentUser : null;

  AuthService() {
    // Listen to authentication changes if Firebase is available
    if (Firebase.apps.isNotEmpty) {
      _auth!.userChanges().listen((User? user) async {
        if (user != null) {
          await _fetchUserModel(user.uid);
        } else {
          _currentUserModel = null;
        }
        notifyListeners();
      });
    }
  }

  // Fetch user model from Firestore
  Future<void> _fetchUserModel(String uid) async {
    if (_db == null || _auth == null) return;
    try {
      DocumentSnapshot doc = await _db!.collection('users').doc(uid).get();
      if (doc.exists) {
        _currentUserModel = UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      } else {
        // If user document does not exist, create it as a customer (e.g. web customer)
        if (_auth!.currentUser != null) {
          _currentUserModel = UserModel(
            uid: uid,
            name: _auth!.currentUser!.displayName ?? 'Customer',
            email: _auth!.currentUser!.email ?? '',
            phoneNumber: '',
            role: 'customer',
            createdAt: DateTime.now(),
          );
          await _db!.collection('users').doc(uid).set(_currentUserModel!.toMap());
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching user model: $e");
    }
  }

  // Sign In
  Future<UserCredential?> signIn(String email, String password) async {
    if (Firebase.apps.isNotEmpty) {
      try {
        UserCredential userCredential = await _auth!.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        await _fetchUserModel(userCredential.user!.uid);
        notifyListeners();
        return userCredential;
      } catch (e) {
        rethrow;
      }
    } else {
      // Mock login: determine role based on email pattern
      String role = 'customer';
      String name = 'Demo Customer';
      if (email.contains('owner') || email.contains('admin')) {
        role = 'owner';
        name = 'Owner KickDirty';
      } else if (email.contains('staff')) {
        role = 'staff';
        name = 'Staff KickDirty';
      }

      _mockUser = UserModel(
        uid: 'mock_uid_${role}',
        name: name,
        email: email.trim(),
        phoneNumber: '08123456789',
        role: role,
        createdAt: DateTime.now(),
      );
      notifyListeners();
      return null;
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
    if (Firebase.apps.isNotEmpty) {
      try {
        UserCredential userCredential = await _auth!.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );

        _currentUserModel = UserModel(
          uid: userCredential.user!.uid,
          name: name.trim(),
          email: email.trim(),
          phoneNumber: phoneNumber.trim(),
          role: role,
          createdAt: DateTime.now(),
        );

        await _db!.collection('users').doc(userCredential.user!.uid).set(_currentUserModel!.toMap());
        notifyListeners();
        return userCredential;
      } catch (e) {
        rethrow;
      }
    } else {
      // Mock register
      _mockUser = UserModel(
        uid: 'mock_uid_${role}_${DateTime.now().millisecondsSinceEpoch}',
        name: name.trim(),
        email: email.trim(),
        phoneNumber: phoneNumber.trim(),
        role: role,
        createdAt: DateTime.now(),
      );
      notifyListeners();
      return null;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    if (Firebase.apps.isNotEmpty) {
      await _auth!.signOut();
      _currentUserModel = null;
    } else {
      _mockUser = null;
    }
    notifyListeners();
  }
}
