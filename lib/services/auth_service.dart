import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

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

  // Fetch user model from Firestore
  Future<void> _fetchUserModel(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        _currentUserModel = UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      } else {
        // If user document does not exist, create it as a customer (e.g. web customer)
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
    } catch (e) {
      if (kDebugMode) print("Error fetching user model: $e");
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

      _currentUserModel = UserModel(
        uid: userCredential.user!.uid,
        name: name.trim(),
        email: email.trim(),
        phoneNumber: phoneNumber.trim(),
        role: role,
        createdAt: DateTime.now(),
      );

      await _db.collection('users').doc(userCredential.user!.uid).set(_currentUserModel!.toMap());
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
