import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PresenceService with WidgetsBindingObserver {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal();

  String? _currentUserId;
  Timer? _heartbeatTimer;
  bool _initialized = false;

  void initialize(String userId) {
    if (_initialized && _currentUserId == userId) return;
    
    // Clean up previous user if any
    stop();

    _currentUserId = userId;
    _initialized = true;

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Set online immediately
    _setPresence(true);

    // Start heartbeat timer every 30 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _keepAlive();
    });
  }

  void stop() {
    if (!_initialized) return;

    // Set offline immediately
    if (_currentUserId != null) {
      _setPresence(false);
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    
    _currentUserId = null;
    _initialized = false;
  }

  Future<void> _setPresence(bool isOnline) async {
    if (_currentUserId == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(_currentUserId).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Document might not have the fields yet, or handle silently
    }
  }

  Future<void> _keepAlive() async {
    if (_currentUserId == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(_currentUserId).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized || _currentUserId == null) return;

    if (state == AppLifecycleState.resumed) {
      _setPresence(true);
      // Restart heartbeat if cancelled
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        _keepAlive();
      });
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _setPresence(false);
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }
}
