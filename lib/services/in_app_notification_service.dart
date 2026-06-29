import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

class InAppNotificationService {
  static final InAppNotificationService instance = InAppNotificationService._();
  InAppNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Cache to track changes and prevent notification spam on startup
  final Map<String, String> _orderStatusCache = {};
  final Map<String, String> _chatRoomMessageCache = {};
  final Map<String, String> _billingInvoiceStatusCache = {};
  
  StreamSubscription? _orderSubscription;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _billingSubscription;
  String? _currentUserId;
  String? _currentUserRole;
  
  bool _isInitialized = false;

  /// Initialize local system notifications
  Future<void> init() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(initializationSettings);
    _isInitialized = true;
  }

  /// Show a system notification bar banner
  Future<void> showSystemNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'kickdirty_updates',
      'KickDirty Updates',
      channelDescription: 'Notifikasi pembaruan pesanan dan pesan masuk KickDirty',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _localNotifications.show(
      id,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  /// Slide-down in-app banner drop overlay
  void showInAppBanner(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _InAppNotificationBannerWidget(
        title: title,
        message: message,
        icon: icon,
        color: color,
        onTap: () {
          overlayEntry.remove();
          if (onTap != null) onTap();
        },
        onDismiss: () {
          overlayEntry.remove();
        },
      ),
    );

    overlayState.insert(overlayEntry);
  }

  /// Start listening to Firestore changes for notifications
  void startListening(BuildContext context, String userId, String role) {
    // Prevent duplicated listeners
    stopListening();

    _currentUserId = userId;
    _currentUserRole = role;

    // Clear caches on new login
    _orderStatusCache.clear();
    _chatRoomMessageCache.clear();

    final db = FirebaseFirestore.instance;

    // 1. Order listener
    if (role == 'owner' || role == 'staff' || role == 'developer') {
      // Listen to all orders
      _orderSubscription = db
          .collection('orders')
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        _handleOrderSnapshot(context, snapshot.docs, isAdminView: true);
      });

      // Listen to all chat rooms for new customer messages
      _chatSubscription = db
          .collection('chat_rooms')
          .orderBy('lastMessageTime', descending: true)
          .snapshots()
          .listen((snapshot) {
        _handleChatSnapshot(context, snapshot.docs, isAdminView: true);
      });

      // Listen to billing invoices if developer role to show notification when owner uploads proof
      if (role == 'developer') {
        _billingSubscription = db
            .collection('developer_billing_invoices')
            .snapshots()
            .listen((snapshot) {
          _handleBillingSnapshot(context, snapshot.docs);
        });
      }
    } else {
      // Customer: Listen only to their own orders
      _orderSubscription = db
          .collection('orders')
          .where('customerId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) {
        _handleOrderSnapshot(context, snapshot.docs, isAdminView: false);
      });

      // Customer: Listen to messages inside their chat room
      _chatSubscription = db
          .collection('chat_rooms')
          .doc(userId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        _handleCustomerChatSnapshot(context, snapshot.docs);
      });
    }
  }

  /// Stop listening to changes (e.g. on logout)
  void stopListening() {
    _orderSubscription?.cancel();
    _chatSubscription?.cancel();
    _billingSubscription?.cancel();
    _orderSubscription = null;
    _chatSubscription = null;
    _billingSubscription = null;
  }

  void _handleOrderSnapshot(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool isAdminView,
  }) {
    for (var doc in docs) {
      final data = doc.data();
      final orderId = doc.id;
      final status = data['status'] as String? ?? '';
      final customerName = data['customerName'] as String? ?? 'Pelanggan';

      if (status.isEmpty) continue;

      final previousStatus = _orderStatusCache[orderId];

      // Update cache
      _orderStatusCache[orderId] = status;

      // Only notify if status has changed and it's not the initial caching run
      if (previousStatus != null && previousStatus != status) {
        String statusLabel = _formatStatusLabel(status);
        String title = '';
        String message = '';
        IconData icon = Icons.info_outline;
        Color color = AppTheme.primaryBlue;

        if (isAdminView) {
          title = 'Pesanan Diperbarui';
          message = 'Pesanan $orderId ($customerName) diupdate ke: $statusLabel';
          icon = Icons.sync_alt;
          color = Colors.orange;
        } else {
          title = 'Status Pesanan Anda';
          message = 'Pesanan $orderId telah diubah ke: $statusLabel';
          icon = Icons.local_shipping_outlined;
          color = AppTheme.primaryBlue;
        }

        // Show native notification bar
        showSystemNotification(
          id: orderId.hashCode,
          title: title,
          body: message,
        );

        // Show in-app banner overlay
        showInAppBanner(
          context,
          title: title,
          message: message,
          icon: icon,
          color: color,
        );
      }
    }
  }

  void _handleChatSnapshot(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool isAdminView,
  }) {
    for (var doc in docs) {
      final data = doc.data();
      final roomId = doc.id;
      final lastMessage = data['lastMessage'] as String? ?? '';
      final customerName = data['customerName'] as String? ?? 'Pelanggan';
      final lastMessageTime = data['lastMessageTime'] as Timestamp?;
      
      // Calculate unread count to make sure it's from the customer
      final unreadCountAdmin = (data['unreadCountAdmin'] as num?)?.toInt() ?? 0;

      if (lastMessage.isEmpty) continue;

      final prevMessage = _chatRoomMessageCache[roomId];
      _chatRoomMessageCache[roomId] = lastMessage;

      // Only notify if message has changed, is not initial caching, and unreadCountAdmin is greater than 0
      if (prevMessage != null && prevMessage != lastMessage && unreadCountAdmin > 0) {
        // Prevent notifying if timestamp is too old (e.g. startup catchup)
        if (lastMessageTime != null &&
            DateTime.now().difference(lastMessageTime.toDate()).inMinutes > 2) {
          continue;
        }

        String title = 'Pesan Baru dari $customerName';
        String message = lastMessage;

        // Show native notification bar
        showSystemNotification(
          id: roomId.hashCode,
          title: title,
          body: message,
        );

        // Show in-app banner overlay
        showInAppBanner(
          context,
          title: title,
          message: message,
          icon: Icons.chat_bubble_outline,
          color: Colors.pink,
        );
      }
    }
  }

  void _handleCustomerChatSnapshot(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return;

    final data = docs.first.data();
    final messageId = docs.first.id;
    final senderId = data['senderId'] as String? ?? '';
    final message = data['message'] as String? ?? '';
    final timestamp = data['timestamp'] as Timestamp?;

    // Only notify if message is from Admin/Shop (not customer themselves)
    if (senderId == _currentUserId || senderId.isEmpty) return;

    final prevMsg = _chatRoomMessageCache[messageId];
    _chatRoomMessageCache[messageId] = message;

    if (prevMsg == null) {
      // Prevent notifying if timestamp is old
      if (timestamp != null &&
          DateTime.now().difference(timestamp.toDate()).inMinutes > 2) {
        return;
      }

      String title = 'Pesan dari KickDirty';
      
      // Show native notification bar
      showSystemNotification(
        id: messageId.hashCode,
        title: title,
        body: message,
      );

      // Show in-app banner overlay
      showInAppBanner(
        context,
        title: title,
        message: message,
        icon: Icons.support_agent_outlined,
        color: AppTheme.primaryBlue,
      );
    }
  }

  String _formatStatusLabel(String status) {
    switch (status) {
      case 'diterima':
        return 'DITERIMA';
      case 'sedang_diproses':
        return 'SEDANG DIPROSES';
      case 'selesai':
        return 'SELESAI';
      case 'diambil':
        return 'SUDAH DISERAHKAN';
      default:
        return status.toUpperCase();
    }
  }

  void _handleBillingSnapshot(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (var doc in docs) {
      final data = doc.data();
      final monthCode = doc.id;
      final status = data['status'] as String? ?? '';
      final updatedAt = data['updatedAt'] as Timestamp?;

      if (status.isEmpty) continue;

      final previousStatus = _billingInvoiceStatusCache[monthCode];

      // Update cache
      _billingInvoiceStatusCache[monthCode] = status;

      // Only notify if status has changed to 'menunggu_konfirmasi' and it's not initial caching
      if (previousStatus != null && previousStatus != status && status == 'menunggu_konfirmasi') {
        // Prevent notifying if timestamp is too old (e.g. startup catchup)
        if (updatedAt != null &&
            DateTime.now().difference(updatedAt.toDate()).inMinutes > 2) {
          continue;
        }

        DateTime parsedMonth = DateTime.now();
        try {
          final parts = monthCode.split('-');
          parsedMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
        } catch (_) {}
        final monthName = DateFormat('MMMM yyyy').format(parsedMonth);

        String title = 'Bukti Bayar Billing Diunggah';
        String message = 'Owner telah mengunggah bukti transfer untuk bulan $monthName. Harap periksa dan konfirmasi.';

        // Show native notification bar
        showSystemNotification(
          id: monthCode.hashCode,
          title: title,
          body: message,
        );

        // Show in-app banner overlay
        showInAppBanner(
          context,
          title: title,
          message: message,
          icon: Icons.receipt_long,
          color: Colors.purple,
        );
      }
    }
  }
}

/// Custom slide-down stateful widget for the in-app notification banner
class _InAppNotificationBannerWidget extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBannerWidget({
    Key? key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<_InAppNotificationBannerWidget> createState() => _InAppNotificationBannerWidgetState();
}

class _InAppNotificationBannerWidgetState extends State<_InAppNotificationBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // Auto dismiss after 4 seconds
    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() async {
    if (mounted) {
      await _controller.reverse();
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _offsetAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  _dismissTimer?.cancel();
                  widget.onTap();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: widget.color.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppTheme.darkBlueText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: AppTheme.textGray),
                        onPressed: _dismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
